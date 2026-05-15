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
    /// `textLayoutManager` whenever it transitions between read and edit
    /// modes (becomes first responder, ends editing, etc.), and the new
    /// manager comes up with a nil delegate — so decorations like
    /// block-LaTeX images / task-checkboxes / code-block fills silently
    /// stop drawing the moment you tap into the editor. Stashing the
    /// delegate here lets us re-attach it on every responder transition.
    var markdownLayoutDelegate: MarkdownLayoutManagerDelegate? {
        didSet { reinstallLayoutDelegate() }
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        // Tap at the end of the note was leaving `MarkdownTextLayoutFragment`
        // instances behind that didn't draw decorations. A full
        // attributedText rebuild via the coordinator's restyle path is the
        // only way that's reliably re-built fragments with our delegate.
        if let coordinator = delegate as? MarkdownTextViewCoordinator {
            coordinator.rebuildFromCurrentBinding()
        }
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

    /// Always re-attaches the layout-manager delegate and force-invalidates
    /// the document range. Called from responder transitions and after
    /// every edit-time restyle. The unconditional invalidate is necessary
    /// because TextKit 2 sometimes creates fragments mid-edit (while
    /// `storage.beginEditing()…endEditing()` is in flight) — if the
    /// `textLayoutManager` is swapped *during* the edit (which UITextView
    /// does on iOS 26 for reasons that aren't documented), those
    /// just-created fragments are vanilla `NSTextLayoutFragment` instances
    /// and our `drawLatexImages` / `drawTaskCheckboxes` overrides never
    /// run. Forcing the invalidate after re-attaching makes TextKit toss
    /// those fragments out and ask the delegate again, which now hands
    /// back `MarkdownTextLayoutFragment` instances.
    func ensureLayoutDelegateAttached() {
        reinstallLayoutDelegate()
    }

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

    // The full `MarkdownEditorConfiguration` lives on the coordinator and the
    // layout-manager delegate's `MarkdownRenderContext`. Holding a copy here
    // tripped a Swift-runtime EXC_BAD_ACCESS during `outlined assign with
    // copy` — copying the configuration's existential-typed `services` field
    // into a UITextView subclass property on iOS 26 crashes the runtime.
}
#endif
