//
//  MarkdownTextViewCoordinator.swift
//  MarkdownEngine
//
//  iOS analogue of `NativeTextViewCoordinator`. Owns the bridging state
//  between the SwiftUI binding and the `MarkdownTextView`, and runs the
//  paragraph-scoped restyle pass on every text change.
//

#if os(iOS) || os(visionOS)
import SwiftUI
import UIKit

public final class MarkdownTextViewCoordinator: NSObject, UITextViewDelegate {
    @Binding var text: String
    @Binding var isWikiLinkActive: Bool

    var documentId: String = "default"
    var fontName: String
    var fontSize: CGFloat
    var configuration: MarkdownEditorConfiguration = .default

    /// Strong reference to the layout-manager delegate so it survives the
    /// `weak` reference TextKit holds.
    var layoutDelegate: MarkdownLayoutManagerDelegate?

    /// Wiki-link `[[Name|<id>]]` metadata for the current document, keyed by
    /// the display-form range. Refreshed every time we rebuild from storage.
    var wikiLinkMetadata: [WikiLinkService.RangeKey: WikiLinkService.LinkMetadata] = [:]

    var lastSyncedText: String = ""
    var didInitialFormatting: Bool = false

    // Embedder callbacks
    var onLinkClick: ((String) -> Void)?
    var onCaretRectChange: ((CGRect) -> Void)?
    var onInlineSelectionChange: ((InlineSelectionState?) -> Void)?
    var onCodeBlockSelectionChange: (([CodeBlockSelection]) -> Void)?

    weak var textView: MarkdownTextView?

    init(
        text: Binding<String>,
        fontName: String,
        fontSize: CGFloat,
        isWikiLinkActive: Binding<Bool>,
        onLinkClick: ((String) -> Void)? = nil,
        onInlineSelectionChange: ((InlineSelectionState?) -> Void)? = nil
    ) {
        self._text = text
        self._isWikiLinkActive = isWikiLinkActive
        self.fontName = fontName
        self.fontSize = fontSize
        self.onLinkClick = onLinkClick
        self.onInlineSelectionChange = onInlineSelectionChange
    }

    // MARK: - Restyling

    /// Rebuilds the entire attributed-string display from the current
    /// `MarkdownTextView.text` and pushes paragraph-scoped attributes through
    /// `TextStylingService`. Called once on initial load and whenever the
    /// document changes externally.
    func rebuildTextStorageAndStyle(_ textView: MarkdownTextView, from text: String, invalidateLayout: Bool) {
        let displayState = WikiLinkService.makeDisplayState(from: text)
        wikiLinkMetadata = displayState.metadata

        let baseFont = PlatformFontMaker.make(name: fontName, size: fontSize)
        textView.baseFont = baseFont

        // Build the full styled attributed string in one shot. The
        // layout-manager delegate must be re-attached *after* `attributedText`
        // is set — UITextView's setter swaps out the live `textLayoutManager`,
        // orphaning our previously-installed delegate and silently disabling
        // `MarkdownTextLayoutFragment` (no checkboxes / code-block fills).
        let attributed = UIKitMarkdownPreview.makeAttributedString(
            text: displayState.display,
            fontName: fontName,
            fontSize: fontSize,
            configuration: configuration
        )

        let selectedRange = textView.selectedRange
        textView.isPerformingProgrammaticEdit = true
        textView.attributedText = attributed
        textView.isPerformingProgrammaticEdit = false

        // Re-set the markdownLayoutDelegate to force the textView to
        // re-attach it to the freshly-swapped textLayoutManager and
        // invalidate the layout so `MarkdownTextLayoutFragment` instances
        // get re-created with image-drawing decorations.
        if let delegate = layoutDelegate {
            textView.markdownLayoutDelegate = delegate
        }

        // Restore caret position if it was still inside the document.
        if selectedRange.location <= textView.textStorage.length {
            textView.selectedRange = selectedRange
        }
        lastSyncedText = text
    }

    private func wikiLinkID(for range: NSRange) -> String? {
        wikiLinkMetadata[WikiLinkService.RangeKey(range)]?.id
    }

    /// Reapply the entire attributed-string display from the binding's
    /// current source. Called by `MarkdownTextView` on responder
    /// transitions where TextKit 2 otherwise loses decoration fragments
    /// (most reliably reproducible by tapping at the very end of the
    /// note).
    func rebuildFromCurrentBinding() {
        guard let textView else { return }
        rebuildTextStorageAndStyle(textView, from: text, invalidateLayout: true)
    }

    // MARK: - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        guard let mdTextView = textView as? MarkdownTextView else { return }
        guard !mdTextView.isPerformingProgrammaticEdit else { return }

        // Restore LaTeX anchor characters before reading the text back to the
        // binding. The styler substitutes anchor chars with U+FFFC so TextKit 2
        // will render the attachment image; we have to reverse that here so
        // the binding never sees a stray U+FFFC.
        let displayText = restoreLatexAnchors(in: mdTextView.textStorage)

        // Propagate the storage-form text (with `[[Name|<id>]]` hydrated)
        // back to the binding so the embedder persists the right thing.
        let storageState = WikiLinkService.makeStorageState(
            from: displayText,
            existingMetadata: wikiLinkMetadata,
            textStorage: mdTextView.textStorage
        )
        wikiLinkMetadata = storageState.metadata
        if storageState.storage != text {
            text = storageState.storage
        }

        // Full attributedText rebuild via the same path `makeUIView` uses.
        // Paragraph-scoped restyling worked in the middle of the document
        // but consistently failed at the trailing edge — pasting / tapping
        // at the end of the document left vanilla `NSTextLayoutFragment`
        // instances in place that bypassed our delegate's
        // `MarkdownTextLayoutFragment`, so LaTeX images and other custom
        // decorations disappeared as soon as the caret landed past the
        // previous trailing newline. The full rebuild re-attributes the
        // entire document and re-attaches the layout delegate so fresh
        // fragments are created uniformly.
        rebuildTextStorageAndStyle(mdTextView, from: text, invalidateLayout: false)

        // Phase C callbacks — keep the embedder's inline-selection state and
        // code-block overlays in sync with the latest text + caret.
        updateInlineSelectionCallbacks(in: textView)
        updateCodeBlockSelection(textView: textView)
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        updateInlineSelectionCallbacks(in: textView)
    }

    /// Walk attachments in `storage`, replace each U+FFFC anchor with the
    /// `originalChar` captured on the attachment, and return the resulting
    /// string in source form (no U+FFFC remaining). Used for both LaTeX
    /// images and task-list checkboxes; both attachment types conform to
    /// `AnchorSubstituteAttachment`.
    private func restoreLatexAnchors(in storage: NSTextStorage) -> String {
        let mutable = NSMutableString(string: storage.string)
        var replacements: [(NSRange, String)] = []
        storage.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: storage.length),
            options: []
        ) { value, range, _ in
            guard let attachment = value as? AnchorSubstituteAttachment else { return }
            replacements.append((range, String(attachment.originalChar)))
        }
        // List bullets: substituted `•` chars carry their original `-`/`*`/`+`
        // on `.listBulletOriginal`. Restore them so the binding preserves
        // the user's source marker style.
        storage.enumerateAttribute(
            .listBulletOriginal,
            in: NSRange(location: 0, length: storage.length),
            options: []
        ) { value, range, _ in
            guard let original = value as? NSString else { return }
            replacements.append((range, original as String))
        }
        // Apply replacements back-to-front so earlier ranges stay valid.
        replacements.sort { $0.0.location > $1.0.location }
        for (range, source) in replacements {
            mutable.replaceCharacters(in: range, with: source)
        }
        return mutable as String
    }
}
#endif
