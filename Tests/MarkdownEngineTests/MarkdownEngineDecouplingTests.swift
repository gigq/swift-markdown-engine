//
//  MarkdownEngineDecouplingTests.swift
//  MarkdownEngineTests
//
//  Smoke tests guarding the engine's decoupling boundary. Each test
//  exercises a protocol-default-implementation path so we catch
//  regressions where engine code accidentally re-introduces a
//  dependency on a concrete app type or singleton.
//

import Testing
import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
@testable import MarkdownEngine

@Suite("Markdown engine decoupling")
struct MarkdownEngineDecouplingTests {

    // MARK: NoOp services stay inert

    @Test func noOpResolverReturnsNil() {
        let resolver = NoOpWikiLinkResolver()
        #expect(resolver.resolve(displayName: "Anything", range: NSRange(location: 0, length: 8)) == nil)
    }

    @Test func noOpImageProviderReturnsNil() {
        let provider = NoOpEmbeddedImageProvider()
        let request = EmbeddedImageRequest(name: "nope")
        #expect(provider.image(for: request) == nil)
    }

    @Test func noOpLatexRendererReturnsNil() {
        let renderer = NoOpLatexRenderer()
        let result = renderer.render(latex: "x^2", fontSize: 14, theme: .default)
        #expect(result == nil)
    }

    @Test func plainTextSyntaxHighlighterReturnsNoHighlighting() {
        let highlighter = PlainTextSyntaxHighlighter()
        #expect(highlighter.highlight(code: "let x = 1", language: "swift") == nil)
        #expect(highlighter.appearanceDidChangeNotification == nil)
    }

    // MARK: WikiLinkService roundtrip

    @Test func wikiLinkRoundtripsThroughDisplayAndStorage() {
        let storage = "Before [[Apple|11111111-2222-3333-4444-555555555555]] after"
        let display = WikiLinkService.makeDisplayState(from: storage)
        #expect(display.display == "Before [[Apple]] after")
        #expect(display.metadata.count == 1)
        let firstID = display.metadata.values.first?.id
        #expect(firstID == "11111111-2222-3333-4444-555555555555")
    }

    @Test func wikiLinkServiceLeavesPlainTextUntouched() {
        let storage = "no links here"
        let display = WikiLinkService.makeDisplayState(from: storage)
        #expect(display.display == storage)
        #expect(display.metadata.isEmpty)
    }

    // MARK: Tokenizer remains pure

    @Test func tokenizerParsesBoldEmphasisAndCode() {
        let tokens = MarkdownTokenizer.parseTokens(in: "**bold** *italic* `code`")
        let kinds = tokens.map(\.kind)
        #expect(kinds.contains(.bold))
        #expect(kinds.contains(.italic))
        #expect(kinds.contains(.inlineCode))
    }

    // MARK: Selection-aware host edit requests

    @Test func editRequestWrapsSelectionAndKeepsTheCoreSelected() {
        let result = MarkdownTextEditResolver.resolve(
            .wrapSelection(prefix: "**", suffix: "**"),
            in: "Before  words  after",
            selectedRange: NSRange(location: 6, length: 9)
        )

        #expect(result.replacement == "  **words**  ")
        #expect(result.selectedRange == NSRange(location: 10, length: 5))
    }

    @Test func editRequestInsertsPairedMarkersAtTheCaret() {
        let result = MarkdownTextEditResolver.resolve(
            .wrapSelection(prefix: "*", suffix: "*"),
            in: "Text",
            selectedRange: NSRange(location: 2, length: 0)
        )

        #expect(result.replacement == "**")
        #expect(result.selectedRange == NSRange(location: 3, length: 0))
    }

    @Test func editRequestReplacesATemplatePlaceholderWithTheSelection() {
        let result = MarkdownTextEditResolver.resolve(
            .insertTemplate(template: "[Link](https://example.com)", placeholder: "Link"),
            in: "Open Typed now",
            selectedRange: NSRange(location: 5, length: 5)
        )

        #expect(result.replacement == "[Typed](https://example.com)")
        #expect(result.selectedRange == NSRange(location: 6, length: 5))
    }

    @Test func editRequestInsertsAtCapturedRevisionAnchor() {
        let result = MarkdownTextEditResolver.resolve(
            .insertTemplateAtAnchor(
                template: "![[Photo.png|resource-id]]",
                anchor: MarkdownTextInsertionAnchor(
                    sourceText: "Before after",
                    selectedRange: NSRange(location: 7, length: 0)
                ),
                replacesSelection: false
            ),
            in: "Before after",
            selectedRange: NSRange(location: 12, length: 0)
        )

        #expect(result.replacementRange == NSRange(location: 7, length: 0))
        #expect(result.replacement == "![[Photo.png|resource-id]]")
        #expect(result.selectedRange == NSRange(location: 33, length: 0))
    }

    @Test func editRequestTranslatesAnchorPastInterveningInsertion() {
        let result = MarkdownTextEditResolver.resolve(
            .insertTemplateAtAnchor(
                template: "image",
                anchor: MarkdownTextInsertionAnchor(
                    sourceText: "Before after",
                    selectedRange: NSRange(location: 7, length: 0)
                ),
                replacesSelection: false
            ),
            in: "New Before after",
            selectedRange: NSRange(location: 0, length: 0)
        )

        #expect(result.replacementRange == NSRange(location: 11, length: 0))
        #expect(result.selectedRange == NSRange(location: 16, length: 0))
    }

    @Test func editRequestMovesInvalidAnchorPastEmojiSurrogatePair() {
        let result = MarkdownTextEditResolver.resolve(
            .insertTemplateAtAnchor(
                template: "image",
                anchor: MarkdownTextInsertionAnchor(
                    sourceText: "A😀B",
                    selectedRange: NSRange(location: 2, length: 0)
                ),
                replacesSelection: false
            ),
            in: "A😀B",
            selectedRange: NSRange(location: 0, length: 0)
        )

        #expect(result.replacementRange == NSRange(location: 3, length: 0))
        #expect(result.selectedRange == NSRange(location: 8, length: 0))
    }

    @Test func anchoredPasteReplacesCapturedSelection() {
        let result = MarkdownTextEditResolver.resolve(
            .insertTemplateAtAnchor(
                template: "image",
                anchor: MarkdownTextInsertionAnchor(
                    sourceText: "Before selected after",
                    selectedRange: NSRange(location: 7, length: 8)
                ),
                replacesSelection: true
            ),
            in: "Before selected after",
            selectedRange: NSRange(location: 0, length: 0)
        )

        #expect(result.replacementRange == NSRange(location: 7, length: 8))
        #expect(result.replacement == "image")
        #expect(result.selectedRange == NSRange(location: 12, length: 0))
    }

    @Test func editRequestAppliesAndRemovesChecklistLineTemplate() {
        let applied = MarkdownTextEditResolver.resolve(
            .applyLineTemplate(template: "- [ ] Todo", placeholder: "Todo"),
            in: "Buy milk",
            selectedRange: NSRange(location: 8, length: 0)
        )
        #expect(applied.replacement == "- [ ] Buy milk")
        #expect(applied.selectedRange == NSRange(location: 14, length: 0))

        let removed = MarkdownTextEditResolver.resolve(
            .applyLineTemplate(template: "- [ ] Todo", placeholder: "Todo"),
            in: applied.replacement,
            selectedRange: applied.selectedRange
        )
        #expect(removed.replacement == "Buy milk")
        #expect(removed.selectedRange == NSRange(location: 8, length: 0))
    }

    @Test func editRequestConvertsBetweenBulletAndChecklistKinds() {
        let bulletFromChecklist = MarkdownTextEditResolver.resolve(
            .applyLineTemplate(template: "- List item", placeholder: "List item"),
            in: "- [ ] Todo",
            selectedRange: NSRange(location: 10, length: 0)
        )
        #expect(bulletFromChecklist.replacement == "- Todo")

        let checklistFromBullet = MarkdownTextEditResolver.resolve(
            .applyLineTemplate(template: "- [ ] Todo", placeholder: "Todo"),
            in: "* Item",
            selectedRange: NSRange(location: 6, length: 0)
        )
        #expect(checklistFromBullet.replacement == "- [ ] Item")
    }

    @Test func editRequestRemovesEquivalentAlternateAndCheckedPrefixes() {
        let alternateBullet = MarkdownTextEditResolver.resolve(
            .applyLineTemplate(template: "- List item", placeholder: "List item"),
            in: "+ Item",
            selectedRange: NSRange(location: 6, length: 0)
        )
        #expect(alternateBullet.replacement == "Item")

        let checkedItem = MarkdownTextEditResolver.resolve(
            .applyLineTemplate(template: "- [ ] Todo", placeholder: "Todo"),
            in: "- [x] Done",
            selectedRange: NSRange(location: 10, length: 0)
        )
        #expect(checkedItem.replacement == "Done")
    }

    @Test func editRequestCyclesHeadingThroughBodyText() {
        let headingTwo = MarkdownTextEditResolver.resolve(
            .cycleHeading(maxLevel: 3),
            in: "# Heading",
            selectedRange: NSRange(location: 9, length: 0)
        )
        #expect(headingTwo.replacement == "## Heading")
        #expect(headingTwo.selectedRange == NSRange(location: 10, length: 0))

        let body = MarkdownTextEditResolver.resolve(
            .cycleHeading(maxLevel: 3),
            in: "### Heading",
            selectedRange: NSRange(location: 11, length: 0)
        )
        #expect(body.replacement == "Heading")
        #expect(body.selectedRange == NSRange(location: 7, length: 0))
    }

    // MARK: Default services container is fully wired with no-ops

    @Test func defaultServicesAreAllNoOps() {
        let services = MarkdownEditorServices.default
        #expect(services.wikiLinks is NoOpWikiLinkResolver)
        #expect(services.images is NoOpEmbeddedImageProvider)
        #expect(services.syntaxHighlighter is PlainTextSyntaxHighlighter)
        #expect(services.latex is NoOpLatexRenderer)
    }

    @Test func defaultBusHasNoNotificationNames() {
        let bus = MarkdownEditorBus.default
        #expect(bus.applyBoldRequest == nil)
        #expect(bus.applyItalicRequest == nil)
        #expect(bus.applyHeadingRequest == nil)
        #expect(bus.selectionBoldDidChange == nil)
        #expect(bus.selectionItalicDidChange == nil)
        #expect(bus.findScrollToRange == nil)
        #expect(bus.findClearHighlights == nil)
    }

    // MARK: Styler runs end-to-end with defaults

    @Test func stylerProducesAttributesWithDefaultServices() {
        let text = "# Heading\n\n**bold** and `code`"
        let ranges = MarkdownStyler.styleAttributes(
            text: text,
            fontName: PlatformFont.systemFont(ofSize: 14).fontName,
            fontSize: 14,
            caretLocation: 0,
            activeTokenIndices: [],
            configuration: .default
        )
        #expect(!ranges.isEmpty)
    }
}
