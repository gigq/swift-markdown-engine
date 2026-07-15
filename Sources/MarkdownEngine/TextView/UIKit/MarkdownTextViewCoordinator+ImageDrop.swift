//
//  MarkdownTextViewCoordinator+ImageDrop.swift
//  MarkdownEngine
//
//  Routes UIKit text drops containing images to the host while preserving
//  a revision-aware anchor represented by the system's drop caret.
//

#if os(iOS)
import UIKit
import UniformTypeIdentifiers

extension MarkdownTextViewCoordinator: UITextDropDelegate {
    public func textDroppableView(
        _ textDroppableView: UIView & UITextDroppable,
        proposalForDrop drop: any UITextDropRequest
    ) -> UITextDropProposal {
        guard onDropImages != nil,
              drop.dropSession.hasItemsConforming(
                toTypeIdentifiers: [UTType.image.identifier]
              ) else {
            return drop.suggestedProposal
        }

        let proposal = UITextDropProposal(operation: .copy)
        proposal.dropAction = .insert
        proposal.dropPerformer = .delegate
        return proposal
    }

    public func textDroppableView(
        _ textDroppableView: UIView & UITextDroppable,
        willPerformDrop drop: any UITextDropRequest
    ) {
        guard let textView = textDroppableView as? MarkdownTextView else { return }
        let providers = drop.dropSession.items
            .map(\.itemProvider)
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        guard !providers.isEmpty else { return }

        let offset = textView.offset(
            from: textView.beginningOfDocument,
            to: drop.dropPosition
        )
        let anchor = insertionAnchor(
            in: textView,
            selectedRange: NSRange(location: max(0, offset), length: 0)
        )
        onDropImages?(providers, anchor)
    }
}
#endif
