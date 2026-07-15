//
//  MarkdownTextViewCoordinator+EditRequests.swift
//  MarkdownEngine
//
//  Applies host formatting requests to the live selection and then enters the
//  same binding/restyling path as a keyboard edit.
//

#if os(iOS) || os(visionOS)
import UIKit

extension MarkdownTextViewCoordinator {
    func apply(_ request: MarkdownTextEditRequest, to textView: MarkdownTextView) {
        textView.unmarkText()
        let sourceText = restoreAnchorSubstitutions(in: textView.textStorage)
        let resolution = MarkdownTextEditResolver.resolve(
            request.edit,
            in: sourceText,
            selectedRange: textView.selectedRange
        )

        let storage = textView.textStorage
        let safeLocation = min(resolution.replacementRange.location, storage.length)
        let safeLength = min(
            resolution.replacementRange.length,
            storage.length - safeLocation
        )
        textView.isPerformingProgrammaticEdit = true
        storage.replaceCharacters(
            in: NSRange(location: safeLocation, length: safeLength),
            with: resolution.replacement
        )
        textView.selectedRange = resolution.selectedRange
        textView.isPerformingProgrammaticEdit = false

        textViewDidChange(textView)
    }
}
#endif
