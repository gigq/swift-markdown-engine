//
//  MarkdownStyler+Tables.swift
//  MarkdownEngine
//
//  GFM-table styling. The separator row (`| --- | --- |`) collapses to a
//  zero-height paragraph so it disappears in the rendered view. Data +
//  header rows use a monospaced font; per-cell kerning pads each cell to
//  its column's max width so columns visually align across rows.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation

extension MarkdownStyler {

    /// Cross-platform monospaced font lookup. Used by tables so the per-cell
    /// padding math is a simple `column-character-deficit * monoCharWidth`.
    private static func monospaceFont(weight: PlatformFont.Weight, size: CGFloat) -> PlatformFont {
        PlatformFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// One cell's parsed shape inside a table row.
    private struct TableCell {
        /// Full character range between two `|` separators (including any
        /// leading/trailing whitespace inside the cell).
        let cellRange: NSRange
        /// Trimmed content range (no leading/trailing whitespace).
        let contentRange: NSRange
        /// Visual width of `contentRange` in monospaced characters.
        let contentLength: Int
    }

    static func styleTables(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        let tableTokens = ctx.tokens.filter {
            $0.kind == .tableRow || $0.kind == .tableSeparator
        }
        guard !tableTokens.isEmpty else { return [] }

        // Sort by document order so we find the header → separator → data
        // sequence by walking adjacency.
        let ordered = tableTokens.sorted { $0.range.location < $1.range.location }

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

            // Parse cells from every row in this group.
            let rowTokens = group.filter { $0.kind == .tableRow }
            var rowsCells: [[TableCell]] = []
            for row in rowTokens {
                rowsCells.append(parseCells(row: row, in: ctx.nsText))
            }

            // Compute the max content-length per column index across all rows.
            let columnCount = rowsCells.map { $0.count }.max() ?? 0
            var maxColumnLength: [Int] = Array(repeating: 0, count: columnCount)
            for cells in rowsCells {
                for (index, cell) in cells.enumerated() {
                    maxColumnLength[index] = max(maxColumnLength[index], cell.contentLength)
                }
            }

            // Width of a single monospaced character at the body font size —
            // the unit the kerning math operates in.
            let monoCharWidth = monoCharacterWidth(size: ctx.baseFont.pointSize)

            for (index, token) in group.enumerated() {
                if MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: ctx.codeTokens) { continue }

                switch token.kind {
                case .tableSeparator:
                    // Collapse to a near-zero-height paragraph so the `| --- |`
                    // line doesn't reserve vertical space.
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
                    let rowFont = isHeader
                        ? monospaceFont(weight: .semibold, size: ctx.baseFont.pointSize)
                        : monospaceFont(weight: .regular, size: ctx.baseFont.pointSize)

                    var rowAttrs: [NSAttributedString.Key: Any] = [.font: rowFont]
                    if isHeader {
                        // Native underline replaces the previous custom-fragment
                        // draw — covers the header text rather than the full
                        // container width, but that's a small visual delta and
                        // it survives any layout-manager swap on iOS.
                        rowAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                        rowAttrs[.underlineColor] = ctx.configuration.theme.mutedText.withAlphaComponent(0.4)
                    }
                    attrs.append((token.range, rowAttrs))

                    // Mute `|` separators so the data reads cleanly.
                    for markerRange in token.markerRanges {
                        attrs.append((markerRange, [
                            .foregroundColor: ctx.configuration.theme.mutedText
                        ]))
                    }

                    // Pad each cell out to its column's max length so the
                    // next column's content starts at the same x in every
                    // row. Kerning the cell's last source character pushes
                    // the trailing `|` rightward by the missing-padding
                    // amount — works without mutating the source text.
                    let rowIndex = rowTokens.firstIndex(where: { $0.range == token.range }) ?? 0
                    let cells = rowsCells[rowIndex]
                    for (colIndex, cell) in cells.enumerated() where colIndex < maxColumnLength.count {
                        let deficit = maxColumnLength[colIndex] - cell.contentLength
                        guard deficit > 0, cell.cellRange.length > 0 else { continue }
                        // Kern the last character of the cell range (the
                        // trailing whitespace, or the last content char if
                        // there's no trailing space).
                        let lastCharRange = NSRange(
                            location: cell.cellRange.location + cell.cellRange.length - 1,
                            length: 1
                        )
                        attrs.append((lastCharRange, [
                            .kern: CGFloat(deficit) * monoCharWidth
                        ]))
                    }

                default:
                    break
                }
            }
        }
        return attrs
    }

    // MARK: - Cell parsing

    /// Walk the `|` markers in a row token and produce a list of cells. A
    /// leading `|` (the row opens with a pipe) means the first "between
    /// pipes" slot is the first real cell; a trailing `|` is similarly
    /// terminal. Both leading and trailing pipes are optional in GFM.
    private static func parseCells(row: MarkdownToken, in text: NSString) -> [TableCell] {
        let pipes = row.markerRanges.sorted { $0.location < $1.location }
        var cells: [TableCell] = []

        let rowStart = row.range.location
        let rowEnd = rowStart + row.range.length

        // Build cell ranges between consecutive pipes (or from row start /
        // before row end if there's no leading/trailing pipe).
        var boundaries: [Int] = []
        // Leading boundary: if first pipe isn't at row start, the row
        // begins with content (no leading `|`); start the first cell at
        // rowStart. Otherwise start it just after the first pipe.
        var firstCellStart = rowStart
        var pipeIterator = 0
        if let firstPipe = pipes.first, firstPipe.location == rowStart {
            firstCellStart = firstPipe.location + firstPipe.length
            pipeIterator = 1
        }
        boundaries.append(firstCellStart)
        for i in pipeIterator..<pipes.count {
            let pipe = pipes[i]
            boundaries.append(pipe.location)         // end of previous cell
            boundaries.append(pipe.location + pipe.length)  // start of next cell
        }
        boundaries.append(rowEnd)

        // Pair boundaries: [start0, end0, start1, end1, ...]
        var pairIndex = 0
        while pairIndex + 1 < boundaries.count {
            let start = boundaries[pairIndex]
            let end = boundaries[pairIndex + 1]
            pairIndex += 2
            guard end > start else { continue }
            let cellRange = NSRange(location: start, length: end - start)
            let trimmed = trimWhitespace(in: cellRange, text: text)
            // Skip a trailing empty cell that's just whitespace after the
            // last `|` (common for `| a | b |` style rows).
            if trimmed.length == 0 && pairIndex == boundaries.count {
                continue
            }
            cells.append(TableCell(
                cellRange: cellRange,
                contentRange: trimmed,
                contentLength: trimmed.length
            ))
        }
        return cells
    }

    private static func trimWhitespace(in range: NSRange, text: NSString) -> NSRange {
        var start = range.location
        var end = range.location + range.length
        while start < end {
            let ch = text.substring(with: NSRange(location: start, length: 1))
            if ch == " " || ch == "\t" { start += 1 } else { break }
        }
        while end > start {
            let ch = text.substring(with: NSRange(location: end - 1, length: 1))
            if ch == " " || ch == "\t" { end -= 1 } else { break }
        }
        return NSRange(location: start, length: end - start)
    }

    private static func monoCharacterWidth(size: CGFloat) -> CGFloat {
        let font = PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular)
        // "M" is the widest glyph in most monospaced fonts but they all
        // share a single advance width — measuring any character returns
        // the same value.
        return ("M" as NSString).size(withAttributes: [.font: font]).width
    }
}
