//
//  ParsedDocument.swift
//  MarkdownEngine
//
//  Cross-platform snapshot of tokenized document used by the coordinator
//  layers on both macOS and iOS to drive inline-selection / code-block
//  callbacks.
//

import Foundation

/// Buckets of `MarkdownToken`s that downstream callback paths
/// (inline-selection, code-block overlay, paragraph restyle scoping)
/// repeatedly need.
struct ParsedDocument {
    let tokens: [MarkdownToken]
    let codeTokens: [MarkdownToken]
    let latexTokens: [MarkdownToken]
    let blockLatexTokens: [MarkdownToken]
    let wikiLinkTokens: [MarkdownToken]
    let imageEmbedTokens: [MarkdownToken]

    /// Pure tokenize-and-bucket pass. Same shape the Mac coordinator's
    /// memoizing `parsedDocument(for:)` produces, exposed here so the iOS
    /// coordinator can build a `ParsedDocument` without going through a
    /// macOS-only path.
    static func parse(_ text: String) -> ParsedDocument {
        let tokens = MarkdownTokenizer.parseTokens(in: text)
        var codeTokens: [MarkdownToken] = []
        var latexTokens: [MarkdownToken] = []
        var blockLatexTokens: [MarkdownToken] = []
        var wikiLinkTokens: [MarkdownToken] = []
        var imageEmbedTokens: [MarkdownToken] = []
        codeTokens.reserveCapacity(tokens.count / 2)
        latexTokens.reserveCapacity(tokens.count / 4)
        blockLatexTokens.reserveCapacity(tokens.count / 4)
        wikiLinkTokens.reserveCapacity(tokens.count / 4)
        for token in tokens {
            switch token.kind {
            case .codeBlock, .inlineCode:
                codeTokens.append(token)
            case .inlineLatex:
                latexTokens.append(token)
            case .blockLatex:
                blockLatexTokens.append(token)
            case .wikiLink:
                wikiLinkTokens.append(token)
            case .imageEmbed:
                imageEmbedTokens.append(token)
            default:
                break
            }
        }
        return ParsedDocument(
            tokens: tokens,
            codeTokens: codeTokens,
            latexTokens: latexTokens,
            blockLatexTokens: blockLatexTokens,
            wikiLinkTokens: wikiLinkTokens,
            imageEmbedTokens: imageEmbedTokens
        )
    }

    /// Find which inline token (if any) the caret at `selectionLocation` is
    /// currently sitting inside. Image-embed tokens win when both match —
    /// image-embed checks the whole paragraph, not just the bracket range.
    func inlineTokenContext(at selectionLocation: Int, in text: NSString) -> InlineTokenContext? {
        for token in imageEmbedTokens
        where token.containsSelectionOrStandaloneParagraph(selectionLocation, in: text)
            && !MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: codeTokens) {
            return .imageEmbed(token: token)
        }

        for token in wikiLinkTokens {
            // Only match when the caret sits between the inner edges of `[[…]]`.
            let start = token.range.location + 2
            let end = NSMaxRange(token.range) - 2
            guard selectionLocation >= start && selectionLocation <= end else { continue }
            guard !MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: codeTokens) else { break }
            return .wikiLink(token: token)
        }

        return nil
    }

    /// Display-form range covering the inline token's markers and content,
    /// used as the anchor rect for popover UIs.
    static func selectionDisplayRange(for token: MarkdownToken, openingMarkerLength: Int) -> NSRange {
        let leftRange = token.markerRanges.first
            ?? NSRange(location: token.range.location, length: min(openingMarkerLength, token.range.length))
        let rightRange = token.markerRanges.last
            ?? NSRange(
                location: max(token.range.location, NSMaxRange(token.range) - min(2, token.range.length)),
                length: min(2, token.range.length)
            )
        return NSRange(
            location: leftRange.location,
            length: rightRange.location + rightRange.length - leftRange.location
        )
    }
}

/// Which inline token (if any) the caret is currently inside. Used by the
/// editor coordinators to drive `InlineSelectionState` callbacks.
enum InlineTokenContext {
    case wikiLink(token: MarkdownToken)
    case imageEmbed(token: MarkdownToken)

    var token: MarkdownToken {
        switch self {
        case .wikiLink(let token), .imageEmbed(let token):
            return token
        }
    }

    var selectionKind: InlineSelectionKind {
        switch self {
        case .wikiLink:
            return .wikiLink
        case .imageEmbed:
            return .imageEmbed
        }
    }
}
