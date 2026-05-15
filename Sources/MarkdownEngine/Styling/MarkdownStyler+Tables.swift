//
//  MarkdownStyler+Tables.swift
//  MarkdownEngine
//
//  Minimal GFM-table styling. The separator row (`| --- | --- |`) is
//  collapsed to a hairline of muted color so it disappears visually while
//  staying in the source. Data + header rows render with the body font but
//  get their `|` separators muted, and the styler asks
//  `MarkdownTextLayoutFragment` to draw a row underline under the header
//  row via the `.tableHeaderRule` attribute.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation

extension MarkdownStyler {

    static func styleTables(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        let tableTokens = ctx.tokens.filter {
            $0.kind == .tableRow || $0.kind == .tableSeparator
        }
        guard !tableTokens.isEmpty else { return [] }

        // Sort by document order so adjacency checks find the header
        // row → separator → data rows sequence.
        let ordered = tableTokens.sorted { $0.range.location < $1.range.location }

        // First pass — group consecutive rows separated only by a single
        // newline into a "table". A table is anchored by a separator row.
        var groups: [[MarkdownToken]] = []
        var current: [MarkdownToken] = []
        for token in ordered {
            if let last = current.last {
                let gapStart = last.range.location + last.range.length
                let gapEnd = token.range.location
                let gap = max(0, gapEnd - gapStart)
                let gapText = gap > 0 ? ctx.nsText.substring(with: NSRange(location: gapStart, length: gap)) : ""
                let onlyWhitespace = gapText.allSatisfy { $0 == "\n" || $0 == " " || $0 == "\t" }
                if gap <= 1 || onlyWhitespace {
                    current.append(token)
                    continue
                }
                groups.append(current)
                current = [token]
            } else {
                current.append(token)
            }
        }
        if !current.isEmpty { groups.append(current) }

        for group in groups {
            let hasSeparator = group.contains(where: { $0.kind == .tableSeparator })
            guard hasSeparator else { continue }

            for (index, token) in group.enumerated() {
                if MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: ctx.codeTokens) { continue }

                switch token.kind {
                case .tableSeparator:
                    // Hide the alignment row — keep it in source but visually
                    // collapsed. Clear color + tiny font + zero-height
                    // paragraph removes the vertical gap entirely.
                    let collapsedParagraph = NSMutableParagraphStyle()
                    collapsedParagraph.minimumLineHeight = 1
                    collapsedParagraph.maximumLineHeight = 1
                    collapsedParagraph.paragraphSpacing = 0
                    collapsedParagraph.paragraphSpacingBefore = 0
                    attrs.append((token.range, [
                        .foregroundColor: PlatformColor.clear,
                        .font: ctx.hiddenMarkerFont,
                        .paragraphStyle: collapsedParagraph
                    ]))
                case .tableRow:
                    let isHeader = index == 0
                    // Mute `|` separators so the data reads cleanly.
                    for markerRange in token.markerRanges {
                        attrs.append((markerRange, [
                            .foregroundColor: ctx.configuration.theme.mutedText
                        ]))
                    }
                    if isHeader {
                        // Bold the header cells.
                        let headerFont = PlatformFontMaker.bold(ctx.baseFont)
                        attrs.append((token.range, [
                            .font: headerFont,
                            .tableHeaderRule: true
                        ]))
                    }
                default:
                    break
                }
            }
        }
        return attrs
    }
}
