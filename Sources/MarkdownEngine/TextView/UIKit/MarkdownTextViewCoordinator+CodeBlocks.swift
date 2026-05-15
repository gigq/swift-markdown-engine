//
//  MarkdownTextViewCoordinator+CodeBlocks.swift
//  MarkdownEngine
//
//  Computes the frames of visible fenced code blocks and forwards them to
//  `onCodeBlockSelectionChange` so embedders can overlay a copy button.
//  iOS port of `NativeTextViewCoordinator+CodeBlocks`; uses TextKit-2's
//  `NSTextLayoutManager.enumerateTextSegments` directly instead of the Mac
//  `LayoutBridge` shim.
//

#if os(iOS) || os(visionOS)
import UIKit

extension MarkdownTextViewCoordinator {
    /// Recompute code-block selection rects and notify the embedder.
    /// Cheap enough to call on every text / selection change; the rect math
    /// is bounded by the number of fenced code blocks in the document.
    func updateCodeBlockSelection(textView: UITextView, tokens: [MarkdownToken]? = nil) {
        guard onCodeBlockSelectionChange != nil else { return }
        guard let textLayoutManager = textView.textLayoutManager,
              let contentManager = textLayoutManager.textContentManager as? NSTextContentStorage else {
            onCodeBlockSelectionChange?([])
            return
        }

        let sourceTokens: [MarkdownToken] = tokens ?? ParsedDocument.parse(textView.text ?? "").tokens
        let codeTokens = sourceTokens.enumerated().filter { $0.element.kind == .codeBlock }
        guard !codeTokens.isEmpty else {
            onCodeBlockSelectionChange?([])
            return
        }

        // Force a full-document layout pass on first selection so the segment
        // rects aren't reported as `.zero` for the off-viewport portion.
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)

        let nsText = (textView.text ?? "") as NSString
        let inset = textView.textContainerInset
        let containerWidth = textView.textContainer.size.width

        let selections: [CodeBlockSelection] = codeTokens.compactMap { (index, token) -> CodeBlockSelection? in
            guard let textRange = textRange(from: token.range, in: contentManager) else {
                return nil
            }
            var bounding: CGRect = .null
            textLayoutManager.enumerateTextSegments(
                in: textRange, type: .standard, options: []
            ) { _, rect, _, _ in
                bounding = bounding.isNull ? rect : bounding.union(rect)
                return true
            }
            guard !bounding.isNull, !bounding.isEmpty else { return nil }

            // Map from text container coordinates to text view coordinates.
            var finalRect = bounding.offsetBy(dx: inset.left, dy: inset.top)
            finalRect.origin.x = inset.left
            finalRect.size.width = containerWidth

            return CodeBlockSelection(
                id: index,
                rect: finalRect,
                language: MarkdownTokenizer.extractLanguage(from: token, in: textView.text ?? ""),
                code: nsText.substring(with: token.contentRange)
            )
        }

        onCodeBlockSelectionChange?(selections)
    }

    private func textRange(from range: NSRange, in storage: NSTextContentStorage) -> NSTextRange? {
        let docStart = storage.documentRange.location
        guard let start = storage.location(docStart, offsetBy: range.location),
              let end = storage.location(start, offsetBy: range.length) else {
            return nil
        }
        return NSTextRange(location: start, end: end)
    }
}
#endif
