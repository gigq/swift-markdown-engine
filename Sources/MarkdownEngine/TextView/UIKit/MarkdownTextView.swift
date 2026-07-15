//
//  MarkdownTextView.swift
//  MarkdownEngine
//
//  UITextView subclass that holds engine-level state (configuration, base
//  font, render context) so the cross-platform layout fragment and the
//  coordinator's restyle path can reach it the same way they reach
//  `NativeTextView` on macOS.
//

#if os(iOS) || os(visionOS)
import UIKit

final class MarkdownTextView: UITextView {

    /// Strong reference to the layout-manager delegate the wrapper installed
    /// on this text view's `textLayoutManager`. UITextView replaces its
    /// `textLayoutManager` on responder transitions (become / resign first
    /// responder, move to window), so we re-attach the delegate from those
    /// hooks. The delegate provides the custom layout-fragment subclass
    /// that draws the still-not-migrated line-spanning chrome (blockquote
    /// rail, horizontal rule, code-block fill, table header rule).
    var markdownLayoutDelegate: MarkdownLayoutManagerDelegate? {
        didSet { reinstallLayoutDelegate() }
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        reinstallLayoutDelegate()
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        reinstallLayoutDelegate()
        return result
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reinstallLayoutDelegate()
    }

    /// Re-attach the layout-manager delegate and invalidate so TextKit 2
    /// rebuilds fragments via our subclass. Called from explicit responder
    /// transition hooks above.
    private func reinstallLayoutDelegate() {
        guard let delegate = markdownLayoutDelegate,
              let textLayoutManager = textLayoutManager else { return }
        textLayoutManager.delegate = delegate
        textLayoutManager.invalidateLayout(for: textLayoutManager.documentRange)
    }

    /// Base body font used for typing attributes and as the fallback the
    /// layout fragment reads when no per-character font is set.
    var baseFont: PlatformFont = PlatformFont.systemFont(ofSize: PlatformFont.systemFontSize)

    /// Toggle used by the coordinator to suppress its own change callbacks
    /// during programmatic edits (e.g. tap-to-toggle checkboxes).
    var isPerformingProgrammaticEdit: Bool = false

    /// Callback the editor invokes when the user pastes an image. Return the
    /// markdown snippet to insert at the caret, or nil to fall through to the
    /// system's default paste behavior.
    var onPasteImage: ((UIPasteboard) -> String?)?

    override func layoutSubviews() {
        super.layoutSubviews()
        keepSelectionVisibleAboveInputAccessory()
    }

    private func keepSelectionVisibleAboveInputAccessory() {
        let obscuredHeight = bounds.intersection(keyboardLayoutGuide.layoutFrame).height
        if abs(contentInset.bottom - obscuredHeight) > 0.5 {
            contentInset.bottom = obscuredHeight
            verticalScrollIndicatorInsets.bottom = obscuredHeight
        }

        guard isFirstResponder,
              obscuredHeight > 0,
              let selection = selectedTextRange else {
            return
        }

        let caret = caretRect(for: selection.end)
        let visibleBottom = bounds.maxY - obscuredHeight
        let overlap = caret.maxY - visibleBottom
        guard overlap > 0.5 else { return }

        let minimumOffset = -adjustedContentInset.top
        let maximumOffset = max(
            minimumOffset,
            contentSize.height + adjustedContentInset.bottom - bounds.height
        )
        let newOffset = min(maximumOffset, max(minimumOffset, contentOffset.y + overlap))
        guard abs(newOffset - contentOffset.y) > 0.5 else { return }
        contentOffset.y = newOffset
    }

    // The full `MarkdownEditorConfiguration` lives on the coordinator and the
    // layout-manager delegate's `MarkdownRenderContext`. Holding a copy here
    // tripped a Swift-runtime EXC_BAD_ACCESS during `outlined assign with
    // copy` — copying the configuration's existential-typed `services` field
    // into a UITextView subclass property on iOS 26 crashes the runtime.
}
#endif
