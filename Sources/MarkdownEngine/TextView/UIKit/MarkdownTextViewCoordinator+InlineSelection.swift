//
//  MarkdownTextViewCoordinator+InlineSelection.swift
//  MarkdownEngine
//
//  Fires the embedder's inline-selection / caret-rect callbacks when the
//  caret enters or leaves a `[[Name]]` wiki-link or `![[Name]]` image-embed
//  token. Mirrors the Mac coordinator's +InlineSelection extension but
//  resolves caret rects via UIKit's `UITextRange` API instead of the
//  AppKit `LayoutBridge` helpers.
//

#if os(iOS) || os(visionOS)
import UIKit

extension MarkdownTextViewCoordinator {

    /// Recompute the inline-selection state for the current caret position
    /// and fire `onInlineSelectionChange` + `onCaretRectChange` if the
    /// embedder is interested.
    func updateInlineSelectionCallbacks(in textView: UITextView) {
        let sourceText = textView.text ?? ""
        let nsText = sourceText as NSString
        let caret = textView.selectedRange.location
        guard caret <= nsText.length else {
            isWikiLinkActive = false
            onInlineSelectionChange?(nil)
            return
        }

        let parsed = ParsedDocument.parse(sourceText)
        guard let context = parsed.inlineTokenContext(at: caret, in: nsText) else {
            isWikiLinkActive = false
            onInlineSelectionChange?(nil)
            return
        }

        let openingMarkerLength = context.selectionKind == .imageEmbed ? 3 : 2
        let displayRange = ParsedDocument.selectionDisplayRange(
            for: context.token,
            openingMarkerLength: openingMarkerLength
        )
        let storageRange = wikiLinkMetadata[WikiLinkService.RangeKey(displayRange)]?.storageRange
        let placeholder: String = {
            guard context.token.contentRange.length > 0 else { return "" }
            return nsText.substring(with: context.token.contentRange)
        }()

        let selection = WikiLinkSelection(
            displayRange: displayRange,
            storageRange: storageRange,
            placeholder: placeholder
        )
        let state = InlineSelectionState(kind: context.selectionKind, selection: selection)

        if context.selectionKind == .wikiLink {
            isWikiLinkActive = true
        }
        onInlineSelectionChange?(state)

        if let rect = caretRect(for: displayRange, in: textView) {
            onCaretRectChange?(rect)
        }
    }

    /// Build a `CGRect` covering `range` in the text view's local coordinate
    /// space using UITextView's `UITextRange` API. Falls back to the bounding
    /// rect of `selectedTextRange` if the range is invalid.
    private func caretRect(for range: NSRange, in textView: UITextView) -> CGRect? {
        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length),
              let textRange = textView.textRange(from: start, to: end) else {
            return nil
        }
        let rect = textView.firstRect(for: textRange)
        return rect.isNull ? nil : rect
    }
}
#endif
