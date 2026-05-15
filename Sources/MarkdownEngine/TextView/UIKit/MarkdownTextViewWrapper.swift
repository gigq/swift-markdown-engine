//
//  MarkdownTextViewWrapper.swift
//  MarkdownEngine
//
//  SwiftUI bridge for the iOS / iPadOS / visionOS Markdown editor.
//  Mirrors the public API surface of the macOS `NativeTextViewWrapper`
//  so embedders can switch between the two with `#if os(macOS)`.
//

#if os(iOS) || os(visionOS)
import SwiftUI
import UIKit

/// SwiftUI bridge for the UIKit-backed MarkdownEngine editor.
///
/// Wraps a `MarkdownTextView` (a `UITextView` subclass) and exposes the same
/// bindings + callbacks the Mac `NativeTextViewWrapper` offers, modulo
/// platform-only features (paste-image, writing tools, find UI, etc.) which
/// land in follow-on phases of the port.
public struct MarkdownTextViewWrapper: UIViewRepresentable {
    public typealias Coordinator = MarkdownTextViewCoordinator
    public typealias UIViewType = UITextView

    @Binding public var text: String
    @Binding public var isWikiLinkActive: Bool
    @Binding public var pendingInlineReplacement: InlineReplacementRequest?

    public var configuration: MarkdownEditorConfiguration
    public var fontName: String
    public var fontSize: CGFloat
    public var documentId: String
    public var isEditable: Bool
    public var onPasteImage: ((UIPasteboard) -> String?)?

    public var onLinkClick: ((String) -> Void)?
    public var onCaretRectChange: ((CGRect) -> Void)?
    public var onInlineSelectionChange: ((InlineSelectionState?) -> Void)?
    public var onCodeBlockSelectionChange: (([CodeBlockSelection]) -> Void)?

    public init(
        text: Binding<String>,
        isWikiLinkActive: Binding<Bool> = .constant(false),
        pendingInlineReplacement: Binding<InlineReplacementRequest?> = .constant(nil),
        configuration: MarkdownEditorConfiguration = .default,
        fontName: String = "SF Pro",
        fontSize: CGFloat = 16,
        documentId: String = "default",
        isEditable: Bool = true,
        onPasteImage: ((UIPasteboard) -> String?)? = nil,
        onLinkClick: ((String) -> Void)? = nil,
        onCaretRectChange: ((CGRect) -> Void)? = nil,
        onInlineSelectionChange: ((InlineSelectionState?) -> Void)? = nil,
        onCodeBlockSelectionChange: (([CodeBlockSelection]) -> Void)? = nil
    ) {
        self._text = text
        self._isWikiLinkActive = isWikiLinkActive
        self._pendingInlineReplacement = pendingInlineReplacement
        self.configuration = configuration
        self.fontName = fontName
        self.fontSize = fontSize
        self.documentId = documentId
        self.isEditable = isEditable
        self.onPasteImage = onPasteImage
        self.onLinkClick = onLinkClick
        self.onCaretRectChange = onCaretRectChange
        self.onInlineSelectionChange = onInlineSelectionChange
        self.onCodeBlockSelectionChange = onCodeBlockSelectionChange
    }

    public func makeCoordinator() -> Coordinator {
        let coordinator = MarkdownTextViewCoordinator(
            text: $text,
            fontName: fontName,
            fontSize: fontSize,
            isWikiLinkActive: $isWikiLinkActive,
            onLinkClick: onLinkClick,
            onInlineSelectionChange: onInlineSelectionChange
        )
        coordinator.documentId = documentId
        coordinator.configuration = configuration
        coordinator.onCaretRectChange = onCaretRectChange
        coordinator.onCodeBlockSelectionChange = onCodeBlockSelectionChange
        return coordinator
    }

    public func makeUIView(context: Context) -> UITextView {
        let textView = MarkdownTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
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
        textView.onPasteImage = onPasteImage

        let baseFont = PlatformFontMaker.make(name: fontName, size: fontSize)
        textView.baseFont = baseFont
        textView.font = baseFont

        // Order matters: `attributedText` must be set BEFORE we attach the
        // layout-manager delegate. The setter swaps out the live
        // `textLayoutManager`, so a pre-installed delegate would be orphaned
        // and `MarkdownTextLayoutFragment` would silently stop drawing
        // checkboxes / code-block fills.
        let displayState = WikiLinkService.makeDisplayState(from: text)
        context.coordinator.wikiLinkMetadata = displayState.metadata
        context.coordinator.lastSyncedText = text

        textView.attributedText = UIKitMarkdownPreview.makeAttributedString(
            text: displayState.display,
            fontName: fontName,
            fontSize: fontSize,
            configuration: configuration
        )

        installLayoutDelegate(on: textView, context: context, baseFont: baseFont)

        context.coordinator.textView = textView
        context.coordinator.fontName = fontName
        context.coordinator.fontSize = fontSize
        context.coordinator.configuration = configuration
        context.coordinator.didInitialFormatting = true
        return textView
    }

    public func updateUIView(_ uiView: UITextView, context: Context) {
        guard let textView = uiView as? MarkdownTextView else { return }
        let coordinator = context.coordinator

        textView.isEditable = isEditable
        textView.onPasteImage = onPasteImage
        coordinator.configuration = configuration
        coordinator.onCaretRectChange = onCaretRectChange
        coordinator.onInlineSelectionChange = onInlineSelectionChange
        coordinator.onCodeBlockSelectionChange = onCodeBlockSelectionChange

        let isDocumentSwitch = coordinator.documentId != documentId
        let fontChanged = coordinator.fontName != fontName || coordinator.fontSize != fontSize

        if let request = pendingInlineReplacement,
           request.documentId == documentId {
            applyInlineReplacement(request, to: textView, coordinator: coordinator)
            DispatchQueue.main.async {
                if self.pendingInlineReplacement?.id == request.id {
                    self.pendingInlineReplacement = nil
                }
            }
            return
        }

        if isDocumentSwitch {
            coordinator.documentId = documentId
            coordinator.didInitialFormatting = false
        }

        if fontChanged {
            coordinator.fontName = fontName
            coordinator.fontSize = fontSize
            let baseFont = PlatformFontMaker.make(name: fontName, size: fontSize)
            textView.baseFont = baseFont
            textView.font = baseFont
            coordinator.layoutDelegate?.renderContext?.baseFont = baseFont
            coordinator.layoutDelegate?.renderContext?.configuration = configuration
        } else {
            coordinator.layoutDelegate?.renderContext?.configuration = configuration
        }

        if coordinator.didInitialFormatting && coordinator.lastSyncedText == text && !fontChanged && !isDocumentSwitch {
            return
        }

        coordinator.rebuildTextStorageAndStyle(textView, from: text, invalidateLayout: isDocumentSwitch || fontChanged)
        coordinator.didInitialFormatting = true
    }

    private func applyInlineReplacement(
        _ request: InlineReplacementRequest,
        to textView: MarkdownTextView,
        coordinator: MarkdownTextViewCoordinator
    ) {
        // For now, perform the replacement against the display text and let
        // the next change cycle re-derive storage form. Wiki-link metadata
        // is rebuilt automatically by `rebuildTextStorageAndStyle`.
        let displayRange = request.selection.displayRange
        let nsText = (textView.text ?? "") as NSString
        guard displayRange.location + displayRange.length <= nsText.length else { return }

        let (displayFragment, _) = WikiLinkService.displayFragmentAndID(from: request.storageFragment)

        textView.isPerformingProgrammaticEdit = true
        let updated = nsText.replacingCharacters(in: displayRange, with: displayFragment)
        textView.text = updated
        textView.isPerformingProgrammaticEdit = false

        coordinator.rebuildTextStorageAndStyle(textView, from: WikiLinkService.makeStorageState(
            from: updated,
            existingMetadata: coordinator.wikiLinkMetadata,
            textStorage: textView.textStorage
        ).storage, invalidateLayout: true)
    }

    private func installLayoutDelegate(
        on textView: MarkdownTextView,
        context: Context,
        baseFont: PlatformFont
    ) {
        guard let textLayoutManager = textView.textLayoutManager else { return }
        let delegate = MarkdownLayoutManagerDelegate()
        delegate.renderContext = MarkdownRenderContext(
            configuration: configuration,
            baseFont: baseFont
        )
        context.coordinator.layoutDelegate = delegate
        textLayoutManager.delegate = delegate
    }
}
#endif
