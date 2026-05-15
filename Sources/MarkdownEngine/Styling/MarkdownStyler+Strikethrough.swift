//
//  MarkdownStyler+Strikethrough.swift
//  MarkdownEngine
//
//  Applies `NSAttributedString.Key.strikethroughStyle` over the content of
//  a `~~text~~` token and dims the `~~` marker glyphs.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation

extension MarkdownStyler {

    static func styleStrikethroughs(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        for token in ctx.tokens where token.kind == .strikethrough {
            if MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: ctx.codeTokens) { continue }

            // Decorate the inner content.
            attrs.append((token.contentRange, [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: ctx.configuration.theme.strikethroughColor
            ]))

            // Soften the `~~` markers — same pattern bold/italic markers use.
            for markerRange in token.markerRanges {
                attrs.append((markerRange, [
                    .foregroundColor: ctx.configuration.theme.mutedText
                ]))
            }
        }
        return attrs
    }
}
