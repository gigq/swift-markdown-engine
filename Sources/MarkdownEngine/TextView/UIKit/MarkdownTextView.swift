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

    /// Catches any `textLayoutManager` swap UITextView performed mid-edit
    /// (paste at end-of-doc, tap-at-end, responder transitions). The earlier
    /// `becomeFirstResponder` / `didMoveToWindow` overrides only catch a
    /// subset of swap points; iOS 26's UITextView swaps the manager from
    /// internal layout passes that aren't tied to any documented hook, so
    /// we re-check on every layout. The guard makes this cheap when the
    /// delegate is already ours.
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let mgr = textLayoutManager,
              let delegate = markdownLayoutDelegate,
              mgr.delegate !== delegate else { return }
        // `invalidateLayout` only, no `ensureLayout` — forcing synchronous
        // layout from within `layoutSubviews` re-enters UIKit's layout pass
        // and asserts. Invalidation alone is enough here because UITextView
        // is already mid-layout and will pick up fresh fragments before
        // drawing on this pass.
        mgr.delegate = delegate
        mgr.invalidateLayout(for: mgr.documentRange)
    }

    func ensureLayoutDelegateAttached() {
        reinstallLayoutDelegate()
    }

    /// Re-attach the layout-manager delegate, invalidate the entire
    /// document range, and force a synchronous layout so any vanilla
    /// `NSTextLayoutFragment` instances created during a manager swap
    /// (before we got to re-attach) get tossed and replaced with
    /// `MarkdownTextLayoutFragment` instances. `invalidateLayout` alone
    /// only marks fragments dirty — TextKit 2 may not actually re-create
    /// them until the next display cycle, and during that window the
    /// vanilla fragments remain on screen with no decorations. `ensureLayout`
    /// forces re-creation now. Do NOT call from `layoutSubviews` — it
    /// re-enters layout and trips UIKit's layout-pass assertions.
    private func reinstallLayoutDelegate() {
        guard let delegate = markdownLayoutDelegate,
              let textLayoutManager = textLayoutManager else { return }
        textLayoutManager.delegate = delegate
        textLayoutManager.invalidateLayout(for: textLayoutManager.documentRange)
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
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
