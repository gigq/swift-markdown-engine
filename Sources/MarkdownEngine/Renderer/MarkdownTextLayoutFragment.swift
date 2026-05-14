//
//  MarkdownTextLayoutFragment.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 12.04.26.
//
//  TextKit 2 replacement for CodeBlockLayoutManager.
//  Draws code-block backgrounds, LaTeX images, and task checkboxes
//  via NSTextLayoutFragment instead of NSLayoutManager glyph overrides.

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation

// Custom attribute keys live in `Internal/MarkdownAttributeKeys.swift` so the
// cross-platform styler can write them without depending on this file.

final class MarkdownTextLayoutFragment: NSTextLayoutFragment {

    // MARK: - FB15131180

    /// Maps to TextKit-2's private `extraLineFragmentAttributes` selector so we can pin the trailing extra-line metrics to body font; otherwise a trailing heading paragraph inflates `usageBoundsForTextContainer` by ~30pt when the caret enters it. Pattern from STTextView.
    @objc(extraLineFragmentAttributes)
    dynamic var stExtraLineFragmentAttributes: NSDictionary?

    // MARK: - Rendering surface

    /// Extend rendering bounds for code-block backgrounds (full container width)
    /// and block images drawn below text via paragraphSpacing.
    override var renderingSurfaceBounds: CGRect {
        var bounds = super.renderingSurfaceBounds
        if hasCodeBlockBackground {
            let containerWidth = textLayoutManager?.textContainer?.size.width ?? bounds.width
            // Extend left to container edge
            bounds.origin.x = -layoutFragmentFrame.origin.x
            bounds.size.width = containerWidth
        }
        // Extend bounds to cover block images that render below the text line
        // (visibleSource mode uses paragraphSpacing to create space for the image).
        for rect in blockImageRects(at: .zero) {
            bounds = bounds.union(rect)
        }
        return bounds
    }

    // MARK: - Drawing

    override func draw(at point: CGPoint, in context: CGContext) {
        // 1. Code-block backgrounds (behind text)
        drawCodeBlockBackground(at: point, in: context)

        // 2. LaTeX images (behind text — hidden markers are invisible anyway)
        drawLatexImages(at: point, in: context)

        // 3. Normal text
        super.draw(at: point, in: context)

        // 4. Task checkboxes (on top of hidden [ ]/[x] markers)
        drawTaskCheckboxes(at: point, in: context)
    }

    // MARK: - Helpers

    /// NSRange in the document for this fragment's content.
    private var fragmentNSRange: NSRange? {
        guard let tcs = textLayoutManager?.textContentManager as? NSTextContentStorage else { return nil }
        let start = tcs.offset(from: tcs.documentRange.location, to: rangeInElement.location)
        let end = tcs.offset(from: tcs.documentRange.location, to: rangeInElement.endLocation)
        guard start != NSNotFound, end != NSNotFound, end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private var textStorage: NSTextStorage? {
        (textLayoutManager?.textContentManager as? NSTextContentStorage)?.textStorage
    }

    /// Returns the drawing position for a character at `docIndex` (document-level NSRange location).
    /// `point` is the draw origin passed to `draw(at:in:)`.
    private func drawPosition(forDocumentCharAt docIndex: Int, point: CGPoint) -> (x: CGFloat, baselineY: CGFloat, lineHeight: CGFloat)? {
        guard let fragRange = fragmentNSRange else { return nil }
        let localIndex = docIndex - fragRange.location
        guard localIndex >= 0 else { return nil }

        // NSTextLineFragment.typographicBounds.origin.y is already relative to the
        // parent layout fragment, so we use it directly — accumulating per-line
        // heights would double-count the inter-line offset on wrapped lines.
        for lineFragment in textLineFragments {
            let lr = lineFragment.characterRange
            if localIndex >= lr.location && localIndex < lr.location + lr.length {
                let charPos = lineFragment.locationForCharacter(at: localIndex)
                let tb = lineFragment.typographicBounds
                return (
                    x: point.x + tb.origin.x + charPos.x,
                    baselineY: point.y + tb.origin.y + charPos.y,
                    lineHeight: tb.height
                )
            }
        }
        return nil
    }

    /// Typographic bounds of the line fragment containing `localIndex`
    /// (index relative to the fragment, not the document).
    private func lineBounds(forLocalIndex localIndex: Int, point: CGPoint) -> CGRect? {
        for lineFragment in textLineFragments {
            let lr = lineFragment.characterRange
            if localIndex >= lr.location && localIndex < lr.location + lr.length {
                let tb = lineFragment.typographicBounds
                return CGRect(x: point.x + lineFragment.glyphOrigin.x + tb.origin.x,
                              y: point.y + tb.origin.y,
                              width: tb.width,
                              height: tb.height)
            }
        }
        return nil
    }

    // MARK: - Context lookup

    /// Pulls configuration/theme/base font from either the Mac
    /// `NativeTextView` (when present) or the delegate-supplied
    /// `MarkdownRenderContext` (used on iOS / by embedders that don't subclass
    /// the text view).
    private var renderContext: MarkdownRenderContext? {
        (textLayoutManager?.delegate as? MarkdownLayoutManagerDelegate)?.renderContext
    }

    private var effectiveConfiguration: MarkdownEditorConfiguration {
        #if os(macOS)
        if let native = textLayoutManager?.textContainer?.textView as? NativeTextView {
            return native.configuration
        }
        #endif
        return renderContext?.configuration ?? .default
    }

    private var effectiveBaseFont: PlatformFont {
        #if os(macOS)
        if let native = textLayoutManager?.textContainer?.textView as? NativeTextView {
            return native.baseFont
        }
        if let font = textLayoutManager?.textContainer?.textView?.font {
            return font
        }
        #endif
        if let ctx = renderContext { return ctx.baseFont }
        return PlatformFont.systemFont(ofSize: PlatformFont.systemFontSize)
    }

    /// `NSTextContainer.textView` is AppKit-only. The iOS read-only preview
    /// has no selection-driven checkbox suppression yet (taps don't move a
    /// caret), so we just return [] there.
    private func currentSelectionRanges() -> [NSRange] {
        #if os(macOS)
        guard let tv = textLayoutManager?.textContainer?.textView else { return [] }
        let values = tv.selectedRanges as? [NSValue] ?? []
        return values.map { $0.rangeValue }.filter { $0.length > 0 }
        #else
        return []
        #endif
    }

    /// Best-effort text-view reference for scale lookups. Mac uses
    /// `NSTextContainer.textView`; iOS has no equivalent so this returns nil
    /// and `PlatformScale` falls back to `UIScreen.main`.
    private var textViewForScale: AnyObject? {
        #if os(macOS)
        return textLayoutManager?.textContainer?.textView
        #else
        return nil
        #endif
    }

    // MARK: - Code Block Background

    private var hasCodeBlockBackground: Bool {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return false }
        let bgColor = ts.attribute(.backgroundColor, at: range.location, effectiveRange: nil) as? PlatformColor
        guard let bgColor else { return false }
        return isCodeBlockBackgroundColor(bgColor)
    }

    private func drawCodeBlockBackground(at point: CGPoint, in context: CGContext) {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return }

        // Only fenced code-block fragments get the full-width fill (first char must carry the code background).
        guard let color = ts.attribute(.backgroundColor, at: range.location, effectiveRange: nil) as? PlatformColor,
              isCodeBlockBackgroundColor(color) else { return }

        let containerWidth = textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width

        var effectiveHeight = layoutFragmentFrame.height
        if textLineFragments.count > 1,
           let lastLF = textLineFragments.last,
           lastLF.characterRange.length == 0 {
            effectiveHeight -= lastLF.typographicBounds.height
        }

        let scale = PlatformScale.backingScale(for: textViewForScale)
        let rawY = point.y
        let rawMaxY = point.y + effectiveHeight
        let snappedY = floor(rawY * scale) / scale
        let snappedMaxY = ceil(rawMaxY * scale) / scale

        // Draw full-width background, clipping out any active selection rects
        // so the system's blue selection highlight remains visible inside code blocks.
        PlatformGraphics.withFlippedContext(context) {
            let bgRect = CGRect(
                x: point.x - layoutFragmentFrame.origin.x,
                y: snappedY,
                width: containerWidth,
                height: snappedMaxY - snappedY
            )

            let selectionRects = selectionRectsInDrawCoordinates(drawPoint: point, snappedY: snappedY, snappedMaxY: snappedMaxY)
            color.setFill()
            if selectionRects.isEmpty {
                PlatformBezierPath(rect: bgRect).fill()
            } else {
                let path = PlatformBezierPath()
                path.setEvenOddFillRule()
                path.appendCrossPlatform(rect: bgRect)
                for r in selectionRects {
                    path.appendCrossPlatform(rect: r.intersection(bgRect))
                }
                path.fill()
            }
        }
    }

    /// Returns active text-selection rectangles intersecting this fragment, in
    /// the same draw-relative coordinate system used by `drawCodeBlockBackground`.
    private func selectionRectsInDrawCoordinates(drawPoint: CGPoint, snappedY: CGFloat, snappedMaxY: CGFloat) -> [CGRect] {
        guard let tlm = textLayoutManager else { return [] }
        var rects: [CGRect] = []

        let dx = drawPoint.x - layoutFragmentFrame.origin.x
        let myRange = self.rangeInElement

        for selection in tlm.textSelections {
            for textRange in selection.textRanges {
                let interStart = textRange.location.compare(myRange.location) == .orderedAscending
                    ? myRange.location : textRange.location
                let interEnd = textRange.endLocation.compare(myRange.endLocation) == .orderedDescending
                    ? myRange.endLocation : textRange.endLocation
                guard interStart.compare(interEnd) == .orderedAscending,
                      let intersection = NSTextRange(location: interStart, end: interEnd) else { continue }

                tlm.enumerateTextSegments(in: intersection, type: .selection, options: []) { _, segFrame, _, _ in
                    // Expand vertically to match the bgRect's snapped span so the
                    // even-odd cut-out is geometrically congruent with the fill.
                    let drawRect = CGRect(
                        x: segFrame.origin.x + dx,
                        y: snappedY,
                        width: segFrame.width,
                        height: snappedMaxY - snappedY
                    )
                    rects.append(drawRect)
                    return true
                }
            }
        }
        return rects
    }

    private func isCodeBlockBackgroundColor(_ color: PlatformColor) -> Bool {
        let highlighter = effectiveConfiguration.services.syntaxHighlighter
        let currentBg = highlighter.backgroundColor()
        guard let lhs = color.rgbComponents(),
              let rhs = currentBg.rgbComponents() else { return false }
        let tolerance: CGFloat = 0.03
        return abs(lhs.red - rhs.red) < tolerance &&
               abs(lhs.green - rhs.green) < tolerance &&
               abs(lhs.blue - rhs.blue) < tolerance
    }

    // MARK: - LaTeX / Block Image Helpers

    /// Compute the draw rect for a block image at `attrRange` using `point` as
    /// the draw origin.  Shared by `drawLatexImages` and `blockImageRects` so
    /// bounds and rendering stay in sync.
    private func blockImageDrawRect(
        attrRange: NSRange,
        imageBounds: CGRect,
        blockOffsetY: CGFloat?,
        point: CGPoint
    ) -> CGRect? {
        guard let pos = drawPosition(forDocumentCharAt: attrRange.location, point: point) else { return nil }
        let localIndex = attrRange.location - (fragmentNSRange?.location ?? 0)
        let lb = lineBounds(forLocalIndex: localIndex, point: point)
        let lineHeight = lb?.height ?? pos.lineHeight
        let lineMinY = lb?.origin.y ?? (pos.baselineY - lineHeight)

        let yPosition: CGFloat
        if let blockOffsetY {
            yPosition = lineMinY + blockOffsetY
        } else {
            yPosition = lineMinY + (lineHeight - imageBounds.height) / 2
        }
        return CGRect(x: pos.x, y: yPosition,
                       width: imageBounds.width, height: imageBounds.height)
    }

    /// Returns the rects of all block images in this fragment, relative to
    /// `point`.  Used by `renderingSurfaceBounds` (with `.zero`) to extend
    /// the surface so images drawn in paragraphSpacing aren't clipped.
    private func blockImageRects(at point: CGPoint) -> [CGRect] {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return [] }
        var rects: [CGRect] = []
        ts.enumerateAttribute(.latexImage, in: range, options: []) { value, attrRange, _ in
            guard value is PlatformImage else { return }
            let isBlock = ts.attribute(.latexIsBlock, at: attrRange.location, effectiveRange: nil) as? Bool ?? false
            guard isBlock else { return }
            let boundsVal = ts.attribute(.latexBounds, at: attrRange.location, effectiveRange: nil) as? NSValue
            let imageBounds = boundsVal?.cgRectValueCross ?? .zero
            let blockOffsetY = ts.attribute(.latexBlockOffsetY, at: attrRange.location, effectiveRange: nil) as? CGFloat
            if let rect = blockImageDrawRect(attrRange: attrRange, imageBounds: imageBounds, blockOffsetY: blockOffsetY, point: point) {
                rects.append(rect)
            }
        }
        return rects
    }

    // MARK: - LaTeX Images

    private func drawLatexImages(at point: CGPoint, in context: CGContext) {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return }

        PlatformGraphics.withFlippedContext(context) {
            ts.enumerateAttribute(.latexImage, in: range, options: []) { [weak self] value, attrRange, _ in
                guard let self, let image = value as? PlatformImage else { return }

                let boundsVal = ts.attribute(.latexBounds, at: attrRange.location, effectiveRange: nil) as? NSValue
                let imageBounds = boundsVal?.cgRectValueCross ?? CGRect(origin: .zero, size: image.size)
                let isBlock = ts.attribute(.latexIsBlock, at: attrRange.location, effectiveRange: nil) as? Bool ?? false
                let blockOffsetY = ts.attribute(.latexBlockOffsetY, at: attrRange.location, effectiveRange: nil) as? CGFloat

                guard let pos = drawPosition(forDocumentCharAt: attrRange.location, point: point) else { return }

                let drawRect: CGRect
                if isBlock {
                    guard let rect = blockImageDrawRect(attrRange: attrRange, imageBounds: imageBounds, blockOffsetY: blockOffsetY, point: point) else { return }
                    drawRect = rect
                } else {
                    let descent = imageBounds.origin.y
                    drawRect = CGRect(x: pos.x,
                                      y: pos.baselineY + descent - imageBounds.height,
                                      width: imageBounds.width, height: imageBounds.height)
                }
                image.draw(in: drawRect)
            }
        }
    }

    // MARK: - Task List Checkboxes

    private func drawTaskCheckboxes(at point: CGPoint, in context: CGContext) {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return }
        let selectionRanges = currentSelectionRanges()

        PlatformGraphics.withFlippedContext(context) {
            ts.enumerateAttribute(.taskCheckbox, in: range, options: []) { [weak self] value, attrRange, _ in
                guard let self, value != nil else { return }
                if selectionRanges.contains(where: { NSIntersectionRange($0, attrRange).length > 0 }) { return }

                let isChecked = (value as? Bool) ?? false
                guard let pos = drawPosition(forDocumentCharAt: attrRange.location, point: point) else { return }

                let font = (ts.attribute(.font, at: attrRange.location, effectiveRange: nil) as? PlatformFont)
                    ?? effectiveBaseFont
                let ascent = max(0, font.ascender)
                let descent = max(0, -font.descender)
                let fontHeight = max(1, ceil(ascent + descent))
                let markerWidth = ("[ ]" as NSString).size(withAttributes: [.font: font]).width
                let size = max(1.0, min(floor(fontHeight * 1.2), floor(markerWidth * 1.2)))
                let boxX = pos.x + max(0, (markerWidth - size) / 2)
                let centerY = pos.baselineY + (descent - ascent) / 2
                let boxY = centerY - size / 2

                let scale = PlatformScale.backingScale(for: textViewForScale)
                func alignToPixel(_ value: CGFloat) -> CGFloat {
                    (value * scale).rounded(.toNearestOrAwayFromZero) / scale
                }
                let boxRect = CGRect(x: alignToPixel(boxX), y: alignToPixel(boxY), width: size, height: size)
                guard !boxRect.isEmpty, !boxRect.isNull else { return }

                let iconInset = max(0.0, size * 0.01)
                let iconRect = boxRect.insetBy(dx: iconInset, dy: iconInset)
                let symbolName = isChecked ? "checkmark.square.fill" : "square"
                let theme = effectiveConfiguration.theme
                let tint = isChecked ? theme.bodyText : theme.mutedText
                if let symbol = PlatformImage.systemSymbol(
                    name: symbolName,
                    pointSize: iconRect.height,
                    hierarchicalTint: tint
                ) {
                    symbol.draw(in: iconRect)
                }
            }
        }
    }
}

// MARK: - Layout Manager Delegate

final class MarkdownLayoutManagerDelegate: NSObject, NSTextLayoutManagerDelegate {
    /// Optional state carrier read by `MarkdownTextLayoutFragment` to find the
    /// configuration / base font when the text view isn't a Mac `NativeTextView`.
    var renderContext: MarkdownRenderContext?

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let fragment = MarkdownTextLayoutFragment(textElement: textElement, range: textElement.elementRange)

        // Seed body font + paragraphStyle so the trailing fragment doesn't
        // inherit heading metrics (FB15131180). Either the Mac NativeTextView
        // provides the metrics or the iOS-side `renderContext` does.
        var seedFont: PlatformFont?
        var seedConfig: MarkdownEditorConfiguration?
        var seedBridge: LayoutBridge?
        var seedTheme: MarkdownEditorTheme?

        #if os(macOS)
        if let textView = textLayoutManager.textContainer?.textView as? NativeTextView {
            seedFont = textView.baseFont
            seedConfig = textView.configuration
            seedBridge = textView.layoutBridge
            seedTheme = textView.configuration.theme
        }
        #endif
        if seedFont == nil, let ctx = renderContext {
            seedFont = ctx.baseFont
            seedConfig = ctx.configuration
            seedBridge = ctx.layoutBridge
            seedTheme = ctx.configuration.theme
        }

        if let seedFont, let seedConfig, let seedTheme {
            let para = NSMutableParagraphStyle()
            let lineHeight = layoutBridgeDefaultLineHeight(for: seedFont, using: seedBridge)
            para.minimumLineHeight = ceil(lineHeight) + seedConfig.paragraph.lineHeightExtraSpacing
            para.paragraphSpacing = ceil(lineHeight * seedConfig.paragraph.spacingFactor)
            para.paragraphSpacingBefore = 0
            fragment.stExtraLineFragmentAttributes = NSDictionary(dictionary: [
                NSAttributedString.Key.font: seedFont,
                NSAttributedString.Key.foregroundColor: seedTheme.bodyText,
                NSAttributedString.Key.paragraphStyle: para
            ])
        }
        return fragment
    }
}
