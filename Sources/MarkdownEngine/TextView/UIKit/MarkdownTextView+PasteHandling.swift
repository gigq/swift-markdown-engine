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
        if hasImage,
           let coordinator = delegate as? MarkdownTextViewCoordinator,
           let onPasteImage {
            onPasteImage(pasteboard, coordinator.insertionAnchor(in: self))
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
}
#endif
