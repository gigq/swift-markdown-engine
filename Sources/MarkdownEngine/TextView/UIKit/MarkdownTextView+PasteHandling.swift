//
//  MarkdownTextView+PasteHandling.swift
//  MarkdownEngine
//
//  iOS analogue of `NativeTextView+PasteHandling`. Intercepts the paste
//  action so embedders can convert pasteboard images into engine-flavored
//  image-embed markdown (`![[name|<id>]]`) before the system inserts plain
//  text.
//

#if os(iOS) || os(visionOS)
import UIKit

extension MarkdownTextView {
    public override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general
        let hasImage = pasteboard.image != nil
            || pasteboard.hasImages
            || (pasteboard.images?.isEmpty == false)
        if hasImage, let snippet = onPasteImage?(pasteboard), !snippet.isEmpty {
            insertPastedSnippet(snippet)
            return
        }
        super.paste(sender)
    }

    public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            let pasteboard = UIPasteboard.general
            if onPasteImage != nil,
               (pasteboard.image != nil || pasteboard.hasImages || (pasteboard.images?.isEmpty == false)) {
                return isEditable
            }
        }
        return super.canPerformAction(action, withSender: sender)
    }

    private func insertPastedSnippet(_ snippet: String) {
        guard isEditable else { return }
        isPerformingProgrammaticEdit = true
        let storage = textStorage
        let selRange = selectedRange
        let safeLoc = min(selRange.location, storage.length)
        let safeLen = min(selRange.length, storage.length - safeLoc)
        let safeRange = NSRange(location: safeLoc, length: safeLen)
        storage.replaceCharacters(in: safeRange, with: snippet)
        let caret = safeLoc + (snippet as NSString).length
        selectedRange = NSRange(location: min(caret, storage.length), length: 0)
        isPerformingProgrammaticEdit = false

        if let coord = delegate as? MarkdownTextViewCoordinator {
            coord.textViewDidChange(self)
        }
    }
}
#endif
