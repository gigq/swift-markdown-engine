//
//  UIKitMarkdownPreview.swift
//  MarkdownEngine
//
//  Read-only Markdown preview for iOS / iPadOS, milestone 1+2 of the
//  iOS port. Uses TextKit 2 via UITextView, the shared cross-platform
//  styler, and the cross-platform `MarkdownTextLayoutFragment` so task
//  checkboxes, code-block backgrounds, inline-code pills, embedded
//  images, and rendered LaTeX show up on iOS the same way they do on
//  Mac.
//
//  Not yet wired:
//    - editing (caret, typing, list helpers)
//    - tap-to-toggle task checkboxes
//    - wiki-link / code-block selection callbacks
//

#if os(iOS) || os(visionOS)
import SwiftUI
import UIKit

/// SwiftUI bridge that renders Markdown read-only on iOS / iPadOS / visionOS.
///
/// Styled output uses the same `MarkdownStyler` the Mac editor does, so heading
/// sizes, emphasis runs, list paragraph styling, link attributes, code-block
/// backgrounds, inline-code pills, task checkboxes, and LaTeX images all
/// match the Mac live editor pixel-for-pixel where the inputs allow.
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

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> UITextView {
        // `usingTextLayoutManager: true` opts in to TextKit 2 so we get
        // `NSTextLayoutFragment` callbacks.
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

        installLayoutDelegate(on: textView, context: context)
        applyAttributedText(to: textView)
        return textView
    }

    public func updateUIView(_ textView: UITextView, context: Context) {
        // Keep the delegate's render context fresh so config / font changes
        // take effect on the next redraw without rebuilding the view.
        let baseFont = PlatformFontMaker.make(name: fontName, size: fontSize)
        if let delegate = context.coordinator.layoutDelegate {
            if delegate.renderContext == nil {
                delegate.renderContext = MarkdownRenderContext(
                    configuration: configuration,
                    baseFont: baseFont
                )
            } else {
                delegate.renderContext?.configuration = configuration
                delegate.renderContext?.baseFont = baseFont
            }
        } else {
            installLayoutDelegate(on: textView, context: context)
        }
        applyAttributedText(to: textView)
    }

    private func installLayoutDelegate(on textView: UITextView, context: Context) {
        guard let textLayoutManager = textView.textLayoutManager else { return }
        let delegate = MarkdownLayoutManagerDelegate()
        delegate.renderContext = MarkdownRenderContext(
            configuration: configuration,
            baseFont: PlatformFontMaker.make(name: fontName, size: fontSize)
        )
        context.coordinator.layoutDelegate = delegate
        textLayoutManager.delegate = delegate
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

    /// Holds the strong reference to the layout-manager delegate (UITextView's
    /// `textLayoutManager.delegate` is weak) so it survives across redraws.
    public final class Coordinator {
        var layoutDelegate: MarkdownLayoutManagerDelegate?
    }
}
#endif
