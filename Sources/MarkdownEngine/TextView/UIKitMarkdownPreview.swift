//
//  UIKitMarkdownPreview.swift
//  MarkdownEngine
//
//  Read-only Markdown preview for iOS / iPadOS, milestone 1 of the
//  iOS port. Uses TextKit 2 via UITextView and the shared
//  cross-platform styler to render an NSAttributedString.
//
//  Not yet wired:
//    - editing (caret, typing, list helpers)
//    - inline image embeds and LaTeX renderings (the rendering surface
//      lives in the Mac-only `MarkdownTextLayoutFragment`)
//    - tap-to-toggle task checkboxes
//    - wiki-link / code-block selection callbacks
//

#if os(iOS) || os(visionOS)
import SwiftUI
import UIKit

/// SwiftUI bridge that renders Markdown read-only on iOS / iPadOS / visionOS.
///
/// Styled output uses the same `MarkdownStyler` the Mac editor does, so heading
/// sizes, emphasis runs, list paragraph styling, and link attributes all match.
/// Inline image embeds and rendered LaTeX are not drawn yet — those use a
/// custom `NSTextLayoutFragment` that's still macOS-only.
public struct UIKitMarkdownPreview: UIViewRepresentable {
    public typealias UIViewType = UITextView

    public var text: String
    public var configuration: MarkdownEditorConfiguration
    public var fontName: String
    public var fontSize: CGFloat

    public init(
        text: String,
        configuration: MarkdownEditorConfiguration = .default,
        fontName: String = "SF Pro",
        fontSize: CGFloat = 16
    ) {
        self.text = text
        self.configuration = configuration
        self.fontName = fontName
        self.fontSize = fontSize
    }

    public func makeUIView(context: Context) -> UITextView {
        // Initializing with `usingTextLayoutManager: true` opts in to TextKit 2.
        let textView = UITextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(
            top: configuration.textInsets.vertical,
            left: configuration.textInsets.horizontal,
            bottom: configuration.textInsets.vertical,
            right: configuration.textInsets.horizontal
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = false
        textView.alwaysBounceVertical = true
        textView.linkTextAttributes = [
            .foregroundColor: configuration.theme.link
        ]
        applyAttributedText(to: textView)
        return textView
    }

    public func updateUIView(_ textView: UITextView, context: Context) {
        applyAttributedText(to: textView)
    }

    private func applyAttributedText(to textView: UITextView) {
        textView.attributedText = Self.makeAttributedString(
            text: text,
            fontName: fontName,
            fontSize: fontSize,
            configuration: configuration
        )
    }

    /// Public helper exposed so embedders can pre-render an attributed string
    /// (e.g. to seed a custom UIView). Same styling MarkdownStyler applies in
    /// the read-only preview.
    public static func makeAttributedString(
        text: String,
        fontName: String = "SF Pro",
        fontSize: CGFloat = 16,
        configuration: MarkdownEditorConfiguration = .default
    ) -> NSAttributedString {
        let baseFont = PlatformFontMaker.make(name: fontName, size: fontSize)
        let defaultLineHeight = baseFont.ascender - baseFont.descender + baseFont.leading
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = ceil(defaultLineHeight) + configuration.paragraph.lineHeightExtraSpacing
        paragraph.lineSpacing = 0
        let baseParagraphSpacing = ceil(defaultLineHeight * configuration.paragraph.spacingFactor)
        paragraph.paragraphSpacing = baseParagraphSpacing
        paragraph.paragraphSpacingBefore = 0
        paragraph.lineBreakMode = .byWordWrapping

        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: baseFont,
                .foregroundColor: configuration.theme.bodyText,
                .paragraphStyle: paragraph
            ]
        )

        let styledRanges = MarkdownStyler.styleAttributes(
            text: text,
            fontName: fontName,
            fontSize: fontSize,
            caretLocation: NSNotFound,
            activeTokenIndices: [],
            configuration: configuration
        )
        for (range, attrs) in styledRanges {
            for (key, value) in attrs {
                guard NSMaxRange(range) <= result.length else { continue }
                result.addAttribute(key, value: value, range: range)
            }
        }
        return result
    }
}
#endif
