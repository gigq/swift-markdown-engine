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
