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

    // MARK: - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        guard let mdTextView = textView as? MarkdownTextView else { return }
        guard !mdTextView.isPerformingProgrammaticEdit else { return }

        // Re-style the paragraph the caret is in, *plus* the paragraph
        // range of every multi-line block token (block LaTeX, fenced code,
        // tables, blockquotes). Without the expansion, a paste of
        // `\[\n…\n\]` would only restyle the line the caret ends up in —
        // the other two lines stay default-styled and the formula doesn't
        // render until the note is closed and reopened (which triggers a
        // full-document rebuild via makeUIView).
        let sourceText = textView.text ?? ""
        let nsString = sourceText as NSString
        let caretLoc = min(textView.selectedRange.location, nsString.length)
        let caretParagraph = nsString.paragraphRange(for: NSRange(location: caretLoc, length: 0))

        let parsed = ParsedDocument.parse(sourceText)
        var paragraphScope: [NSRange] = [caretParagraph]
        for token in parsed.tokens {
            switch token.kind {
            case .blockLatex, .codeBlock, .tableRow, .tableSeparator, .blockquote:
                paragraphScope.append(nsString.paragraphRange(for: token.range))
            default:
                break
            }
        }

        let style = TextStylingService.makeBaseFontAndStyle(
            fontName: fontName,
            fontSize: fontSize,
            configuration: configuration
        )
        TextStylingService.restyle(
            textView: mdTextView,
            paragraphCandidates: paragraphScope,
            baseFont: style.font,
            paragraphStyle: style.style,
            caretLocation: caretLoc,
            activeTokenIndices: [],
            wikiLinkIDProvider: { [weak self] range in
                self?.wikiLinkID(for: range)
            },
            precomputedTokens: parsed.tokens,
            configuration: configuration
        )

        // Propagate the storage-form text (with `[[Name|<id>]]` hydrated)
        // back to the binding so the embedder persists the right thing.
        let storageState = WikiLinkService.makeStorageState(
            from: textView.text ?? "",
            existingMetadata: wikiLinkMetadata,
            textStorage: mdTextView.textStorage
        )
        wikiLinkMetadata = storageState.metadata
        if storageState.storage != text {
            text = storageState.storage
            lastSyncedText = storageState.storage
        }

        // Phase C callbacks — keep the embedder's inline-selection state and
        // code-block overlays in sync with the latest text + caret.
        updateInlineSelectionCallbacks(in: textView)
        updateCodeBlockSelection(textView: textView)
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        updateInlineSelectionCallbacks(in: textView)
    }
}
#endif
