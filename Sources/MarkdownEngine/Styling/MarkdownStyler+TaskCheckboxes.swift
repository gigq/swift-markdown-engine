//
//  MarkdownStyler+TaskCheckboxes.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 16.03.26.
//
//  GitHub-style `- [ ] / - [x]` task checkbox styling and strike-through.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation

extension MarkdownStyler {

    // MARK: Task List Checkboxes

    static func styleTaskCheckboxes(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        let taskMatches = MarkdownStyler.taskListRegex.matches(in: ctx.text, options: [], range: ctx.fullRange)
        for match in taskMatches {
            let markerRange = match.range(at: 2)
            let spacerRange = match.range(at: 3)
            let checkboxRange = match.range(at: 4)
            if checkboxRange.location == NSNotFound { continue }
            if MarkdownDetection.isInsideCodeBlock(range: checkboxRange, codeTokens: ctx.codeTokens) { continue }
            let checkboxText = ctx.nsText.substring(with: checkboxRange)
            let isChecked = checkboxText.range(of: "[x]", options: [.caseInsensitive]) != nil
            if markerRange.location != NSNotFound {
                let syntaxStart = markerRange.location
                let syntaxEnd = checkboxRange.location + checkboxRange.length
                let syntaxRange = NSRange(location: syntaxStart, length: max(0, syntaxEnd - syntaxStart))
                var isActiveSyntax = NSLocationInRange(ctx.caretLocation, syntaxRange)
                if !isActiveSyntax && ctx.caretLocation == syntaxEnd {
                    let lastIndex = syntaxEnd - 1
                    if lastIndex >= syntaxStart && lastIndex < ctx.nsText.length {
                        let lastChar = ctx.nsText.substring(with: NSRange(location: lastIndex, length: 1))
                        if lastChar != "\n" { isActiveSyntax = true }
                    }
                }
                if isChecked {
                    let lineRange = ctx.nsText.lineRange(for: checkboxRange)
                    var lineEnd = lineRange.location + lineRange.length
                    if lineEnd > lineRange.location {
                        let lastCharRange = NSRange(location: lineEnd - 1, length: 1)
                        if ctx.nsText.substring(with: lastCharRange) == "\n" {
                            lineEnd -= 1
                        }
                    }
                    var contentStart = checkboxRange.location + checkboxRange.length
                    while contentStart < lineEnd {
                        let charRange = NSRange(location: contentStart, length: 1)
                        let char = ctx.nsText.substring(with: charRange)
                        if char == " " || char == "\t" {
                            contentStart += 1
                            continue
                        }
                        break
                    }
                    if contentStart < lineEnd {
                        attrs.append((NSRange(location: contentStart, length: lineEnd - contentStart), [
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                            .strikethroughColor: ctx.configuration.theme.strikethroughColor
                        ]))
                    }
                }
                if isActiveSyntax { continue }
                let afterCheckboxIndex = checkboxRange.location + checkboxRange.length
                if afterCheckboxIndex < ctx.nsText.length {
                    let spaceRange = NSRange(location: afterCheckboxIndex, length: 1)
                    let spaceChar = ctx.nsText.substring(with: spaceRange)
                    if spaceChar == " " && !isChecked {
                        let extraSpacing = HeadingHelpers.checkboxExtraSpacing(
                            font: ctx.baseFont,
                            configuration: ctx.configuration.checkbox
                        )
                        attrs.append((spaceRange, [.kern: extraSpacing]))
                    }
                }
            }
            // Build the SF Symbol checkbox image now so it can ride on the
            // attachment that replaces the marker character. Sizing mirrors
            // the (now-deprecated) custom-fragment draw path so the visual
            // ends up identical to what users had before.
            let font = ctx.baseFont
            let ascent = max(0, font.ascender)
            let descent = max(0, -font.descender)
            let fontHeight = max(1, ceil(ascent + descent))
            let markerWidth = HeadingHelpers.textWidth("[ ]", font: font)
            let boxSize = max(1.0, min(floor(fontHeight * 1.2), floor(markerWidth * 1.2)))
            let symbolName = isChecked ? "checkmark.square.fill" : "square"
            let tint: PlatformColor = isChecked
                ? ctx.configuration.theme.bodyText
                : ctx.configuration.theme.mutedText
            let symbol = PlatformImage.systemSymbol(
                name: symbolName,
                pointSize: boxSize,
                hierarchicalTint: tint
            )

            if markerRange.location != NSNotFound, let symbol {
                // Substitute the marker `-` itself with the checkbox attachment
                // — that puts the glyph at column 0 of the line, matching the
                // previous fragment-draw placement. UIKitMarkdownPreview swaps
                // in U+FFFC after styling so TextKit 2 actually renders the
                // attachment image (it ignores `.attachment` on regular chars).
                let markerChar = ctx.nsText.substring(with: markerRange).first ?? "-"
                // Center the icon vertically on the font's x-height area.
                let attachmentY = (ascent - descent) / 2 - boxSize / 2
                let attachment = CheckboxAttachment(
                    image: symbol,
                    bounds: CGRect(x: 0, y: attachmentY, width: boxSize, height: boxSize),
                    originalChar: markerChar,
                    isChecked: isChecked
                )
                attrs.append((markerRange, [
                    .attachment: attachment,
                    .taskCheckbox: isChecked
                ]))
            } else if markerRange.location != NSNotFound {
                // Symbol lookup failed (shouldn't happen on Apple platforms,
                // but be defensive) — fall back to hiding the marker so the
                // line at least isn't visually broken.
                attrs.append((markerRange, [.foregroundColor: PlatformColor.clear]))
            }

            // Hide the surrounding source characters (` `, `[`, ` `/`x`, `]`)
            // and collapse their advance so the visible width of the row is
            // just the attachment + a separator space. We borrow the tiny-
            // marker-font + matching-kerning trick used by the inline-LaTeX
            // hide path: render the chars at near-zero size, then negate
            // that tiny advance.
            if spacerRange.location != NSNotFound {
                let spacerText = ctx.nsText.substring(with: spacerRange)
                attrs.append((spacerRange, [
                    .foregroundColor: PlatformColor.clear,
                    .font: ctx.latexMarkerFont,
                    .kern: -HeadingHelpers.textWidth(spacerText, font: ctx.latexMarkerFont)
                ]))
            }
            // Note: `.taskCheckbox` rides on the marker (the attachment anchor)
            // only — users tap the visible checkbox glyph, which is the
            // attachment at column 0. The `[ ]` source range is fully hidden
            // (zero-width via tiny font + kerning) so it can't receive taps.
            attrs.append((checkboxRange, [
                .foregroundColor: PlatformColor.clear,
                .font: ctx.latexMarkerFont,
                .kern: -HeadingHelpers.textWidth(checkboxText, font: ctx.latexMarkerFont)
            ]))
        }
        return attrs
    }
}
