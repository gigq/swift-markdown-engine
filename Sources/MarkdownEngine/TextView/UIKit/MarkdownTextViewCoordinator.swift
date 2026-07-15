//
//  MarkdownTextViewCoordinator.swift
//  MarkdownEngine
//
//  iOS analogue of `NativeTextViewCoordinator`. Owns the bridging state
//  between the SwiftUI binding and the `MarkdownTextView`, and runs a full
//  attributedText rebuild on every text change so the U+FFFC anchor
//  substitutions stay in sync with the styler output.
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
    var documentGeneration = 0
    var queuedTextEditRequestID: UUID?
    var cancelledTextEditRequestID: UUID?
    var completedTextEditRequestID: UUID?

    // Embedder callbacks
    var onLinkClick: ((String) -> Void)?
    var onCaretRectChange: ((CGRect) -> Void)?
    var onInlineSelectionChange: ((InlineSelectionState?) -> Void)?
    var onCodeBlockSelectionChange: (([CodeBlockSelection]) -> Void)?
    var onDropImages: (([NSItemProvider], MarkdownTextInsertionAnchor) -> Void)?
    var onInsertionAnchorChange: ((MarkdownTextInsertionAnchor) -> Void)?
    var onTextEditRequestCompletion: ((UUID, MarkdownTextEditRequestResult) -> Void)?

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
    /// binding text and applies the U+FFFC anchor substitutions. Called on
    /// initial load, on every text change, and whenever the document
    /// changes externally.
    func rebuildTextStorageAndStyle(_ textView: MarkdownTextView, from text: String) {
        let displayState = WikiLinkService.makeDisplayState(from: text)
        wikiLinkMetadata = displayState.metadata

        let baseFont = PlatformFontMaker.make(name: fontName, size: fontSize)
        textView.baseFont = baseFont

        // Build the styled attributed string. `makeAttributedString` runs
        // the styler and then substitutes anchor characters with U+FFFC so
        // TextKit 2 renders the attachment images (LaTeX, checkboxes).
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

        // Re-attach the layout-manager delegate so the custom fragment
        // subclass renders the still-not-migrated line-spanning chrome
        // (blockquote rail, horizontal rule, code-block fill, table header
        // rule). Setting `attributedText` swaps the live `textLayoutManager`
        // and the new manager comes up with a nil delegate.
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

    // MARK: - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        guard let mdTextView = textView as? MarkdownTextView else { return }
        guard !mdTextView.isPerformingProgrammaticEdit else { return }

        // Reverse the U+FFFC anchor substitution (and the bullet `•`
        // substitution) before reading the text back to the binding so the
        // binding always sees source-form markdown.
        let displayText = restoreAnchorSubstitutions(in: mdTextView.textStorage)

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

        // Full rebuild so freshly-typed tokens get their attachments and
        // U+FFFC substitutions applied. Paragraph-scoped restyling is what
        // Mac uses, but it doesn't carry the post-styling substitution loop,
        // so iOS does the simpler full rebuild for now.
        rebuildTextStorageAndStyle(mdTextView, from: text)

        // Phase C callbacks — keep the embedder's inline-selection state and
        // code-block overlays in sync with the latest text + caret.
        updateInlineSelectionCallbacks(in: textView)
        updateCodeBlockSelection(textView: textView)
        onInsertionAnchorChange?(insertionAnchor(in: mdTextView))
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        updateInlineSelectionCallbacks(in: textView)
        guard let textView = textView as? MarkdownTextView else { return }
        onInsertionAnchorChange?(insertionAnchor(in: textView))
    }

    func insertionAnchor(
        in textView: MarkdownTextView,
        selectedRange: NSRange? = nil
    ) -> MarkdownTextInsertionAnchor {
        MarkdownTextInsertionAnchor(
            sourceText: restoreAnchorSubstitutions(in: textView.textStorage),
            selectedRange: selectedRange ?? textView.selectedRange
        )
    }

    /// Walk all post-styling substitutions in `storage` and reverse them
    /// — U+FFFC + `AnchorSubstituteAttachment` (LaTeX images, checkboxes)
    /// get the attachment's `originalChar` back, and `•` bullet glyphs
    /// carrying `.listBulletOriginal` get their source `-`/`*`/`+` back.
    /// Returns the resulting string in source form ready for the binding.
    func restoreAnchorSubstitutions(in storage: NSTextStorage) -> String {
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
