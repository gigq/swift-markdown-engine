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

        if let textLayoutManager = textView.textLayoutManager,
           let delegate = layoutDelegate {
            textLayoutManager.delegate = delegate
        }

        if invalidateLayout, let textLayoutManager = textView.textLayoutManager {
            textLayoutManager.invalidateLayout(for: textLayoutManager.documentRange)
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

        // Re-style only the paragraph the caret is currently in. Cheap and
        // keeps unrelated paragraphs from re-flowing while the user types.
        let nsString = (textView.text ?? "") as NSString
        let caretLoc = min(textView.selectedRange.location, nsString.length)
        let paragraphRange = nsString.paragraphRange(for: NSRange(location: caretLoc, length: 0))

        let style = TextStylingService.makeBaseFontAndStyle(
            fontName: fontName,
            fontSize: fontSize,
            configuration: configuration
        )
        TextStylingService.restyle(
            textView: mdTextView,
            paragraphCandidates: [paragraphRange],
            baseFont: style.font,
            paragraphStyle: style.style,
            caretLocation: caretLoc,
            activeTokenIndices: [],
            wikiLinkIDProvider: { [weak self] range in
                self?.wikiLinkID(for: range)
            },
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
