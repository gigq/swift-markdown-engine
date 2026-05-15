//
//  MarkdownStyler+Blockquote.swift
//  MarkdownEngine
//
//  Per-line blockquote styling: paragraph indented to clear room for a left
//  vertical bar, marker text dimmed (we leave it visible so editing a quote
//  line keeps the `>` source intact). The actual vertical bar is drawn by
//  `MarkdownTextLayoutFragment` when it sees a `.blockquoteBar` attribute on
//  the paragraph.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation

extension MarkdownStyler {

    static func styleBlockquotes(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        for token in ctx.tokens where token.kind == .blockquote {
            if MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: ctx.codeTokens) { continue }

            let paragraph = NSMutableParagraphStyle()
            let lineHeight = ceil(layoutBridgeDefaultLineHeight(for: ctx.baseFont, using: ctx.layoutBridge))
            paragraph.minimumLineHeight = lineHeight + ctx.configuration.paragraph.lineHeightExtraSpacing
            paragraph.lineSpacing = 0
            paragraph.paragraphSpacing = 0
            paragraph.paragraphSpacingBefore = 0
            paragraph.headIndent = 20
            paragraph.firstLineHeadIndent = 20

            attrs.append((token.range, [
                .paragraphStyle: paragraph,
                .blockquoteBar: true
            ]))

            for markerRange in token.markerRanges {
                attrs.append((markerRange, [
                    .foregroundColor: ctx.configuration.theme.mutedText
                ]))
            }
            attrs.append((token.contentRange, [
                .foregroundColor: ctx.configuration.theme.mutedText
            ]))
        }
        return attrs
    }
}
