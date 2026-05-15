//
//  MarkdownStyler+ListBullets.swift
//  MarkdownEngine
//
//  Replaces the literal `-` / `*` / `+` marker of an unordered list item
//  with a `•` glyph drawn by `MarkdownTextLayoutFragment`. Mirrors the way
//  task checkboxes hide their `[ ]` source and overlay a custom symbol —
//  same intent, same hide-marker-then-tag pattern.
//
//  Ordered list items (`1.`, `2.`) keep their numbers visible.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation

extension MarkdownStyler {

    /// Regex that matches an unordered list line and captures the marker
    /// character (`-` / `•` / `*` / `+`). The lookahead requires whitespace
    /// after the marker so we don't accidentally style `*emphasis*` or
    /// `+function()` text as a list bullet.
    static let unorderedListMarkerRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)([-•*+])(?=[ \t])"#,
        options: [.anchorsMatchLines]
    )

    static func styleListBullets(_ ctx: StylingContext) -> [StyledRange] {
        guard ctx.configuration.lists.helpersEnabled else { return [] }
        var attrs: [StyledRange] = []

        let matches = unorderedListMarkerRegex.matches(in: ctx.text, options: [], range: ctx.fullRange)
        for match in matches {
            let markerRange = match.range(at: 2)
            guard markerRange.length > 0 else { continue }

            // Skip inside fenced code blocks.
            if MarkdownDetection.isInsideCodeBlock(range: markerRange, codeTokens: ctx.codeTokens) { continue }

            // Don't override the task-checkbox path — `- [ ]` is a separate
            // styler pass that already hides the `-` and draws a checkbox.
            // Detection: check if the next non-space chars on the line are
            // `[<space|x|X>]`.
            let afterMarker = markerRange.location + markerRange.length
            var probe = afterMarker
            let nsText = ctx.nsText
            while probe < nsText.length {
                let ch = nsText.substring(with: NSRange(location: probe, length: 1))
                if ch == " " || ch == "\t" { probe += 1; continue }
                break
            }
            if probe + 2 < nsText.length {
                let openBracket = nsText.substring(with: NSRange(location: probe, length: 1))
                let inner = nsText.substring(with: NSRange(location: probe + 1, length: 1))
                let closeBracket = nsText.substring(with: NSRange(location: probe + 2, length: 1))
                if openBracket == "[" && closeBracket == "]"
                    && (inner == " " || inner == "x" || inner == "X") {
                    continue
                }
            }

            // Don't hide the marker while the caret is sitting on the line —
            // keeps the source visible/editable when you're actively typing
            // there, same UX as bold/italic markers.
            let lineRange = nsText.lineRange(for: markerRange)
            let caretOnLine = NSLocationInRange(ctx.caretLocation, lineRange)
                || ctx.caretLocation == lineRange.location + lineRange.length
            if caretOnLine { continue }

            attrs.append((markerRange, [
                .foregroundColor: PlatformColor.clear,
                .listBullet: true
            ]))
        }
        return attrs
    }
}
