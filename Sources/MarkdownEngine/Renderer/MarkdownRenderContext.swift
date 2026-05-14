//
//  MarkdownRenderContext.swift
//  MarkdownEngine
//
//  Carrier the layout-manager delegate hands to each
//  `MarkdownTextLayoutFragment`. Lets the fragment reach the configuration,
//  theme, and base font without depending on the AppKit `NativeTextView`
//  subclass (which doesn't exist on iOS).
//

import Foundation

/// Minimal state the layout fragment needs to render decorations.
///
/// On macOS the fragment can additionally reach
/// `NativeTextView.configuration` directly; on iOS this carrier is the only
/// source of truth.
final class MarkdownRenderContext {
    var configuration: MarkdownEditorConfiguration
    var baseFont: PlatformFont
    /// Optional bridge for line-height queries. The Mac editor wires one of
    /// these in. iOS leaves it nil for the read-only preview.
    var layoutBridge: LayoutBridge?

    init(
        configuration: MarkdownEditorConfiguration,
        baseFont: PlatformFont,
        layoutBridge: LayoutBridge? = nil
    ) {
        self.configuration = configuration
        self.baseFont = baseFont
        self.layoutBridge = layoutBridge
    }
}
