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
    @Binding public var pendingTextEditRequest: MarkdownTextEditRequest?

    public var configuration: MarkdownEditorConfiguration
    public var fontName: String
    public var fontSize: CGFloat
    public var documentId: String
    public var isEditable: Bool
    public var inputAccessoryContent: (() -> AnyView)?
    public var onPasteImage: ((UIPasteboard, MarkdownTextInsertionAnchor) -> Void)?
    public var onDropImages: (([NSItemProvider], MarkdownTextInsertionAnchor) -> Void)?
    public var onInsertionAnchorChange: ((MarkdownTextInsertionAnchor) -> Void)?
    public var onTextEditRequestCompletion: ((UUID, MarkdownTextEditRequestResult) -> Void)?

    public var onLinkClick: ((String) -> Void)?
    public var onCaretRectChange: ((CGRect) -> Void)?
    public var onInlineSelectionChange: ((InlineSelectionState?) -> Void)?
    public var onCodeBlockSelectionChange: (([CodeBlockSelection]) -> Void)?

    public init(
        text: Binding<String>,
        isWikiLinkActive: Binding<Bool> = .constant(false),
        pendingInlineReplacement: Binding<InlineReplacementRequest?> = .constant(nil),
        pendingTextEditRequest: Binding<MarkdownTextEditRequest?> = .constant(nil),
        configuration: MarkdownEditorConfiguration = .default,
        fontName: String = "SF Pro",
        fontSize: CGFloat = 16,
        documentId: String = "default",
        isEditable: Bool = true,
        inputAccessoryContent: (() -> AnyView)? = nil,
        onPasteImage: ((UIPasteboard, MarkdownTextInsertionAnchor) -> Void)? = nil,
        onDropImages: (([NSItemProvider], MarkdownTextInsertionAnchor) -> Void)? = nil,
        onInsertionAnchorChange: ((MarkdownTextInsertionAnchor) -> Void)? = nil,
        onTextEditRequestCompletion: ((UUID, MarkdownTextEditRequestResult) -> Void)? = nil,
        onLinkClick: ((String) -> Void)? = nil,
        onCaretRectChange: ((CGRect) -> Void)? = nil,
        onInlineSelectionChange: ((InlineSelectionState?) -> Void)? = nil,
        onCodeBlockSelectionChange: (([CodeBlockSelection]) -> Void)? = nil
    ) {
        self._text = text
        self._isWikiLinkActive = isWikiLinkActive
        self._pendingInlineReplacement = pendingInlineReplacement
        self._pendingTextEditRequest = pendingTextEditRequest
        self.configuration = configuration
        self.fontName = fontName
        self.fontSize = fontSize
        self.documentId = documentId
        self.isEditable = isEditable
        self.inputAccessoryContent = inputAccessoryContent
        self.onPasteImage = onPasteImage
        self.onDropImages = onDropImages
        self.onInsertionAnchorChange = onInsertionAnchorChange
        self.onTextEditRequestCompletion = onTextEditRequestCompletion
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
        coordinator.onDropImages = onDropImages
        coordinator.onInsertionAnchorChange = onInsertionAnchorChange
        coordinator.onTextEditRequestCompletion = onTextEditRequestCompletion
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
        #if os(iOS)
        textView.textDropDelegate = context.coordinator
        updateInputAccessory(on: textView)
        #endif

        let baseFont = PlatformFontMaker.make(name: fontName, size: fontSize)
        textView.baseFont = baseFont
        textView.font = baseFont
        textView.installCheckboxTapHandler()
        textView.applyDefaultTextBehaviors()

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
        DispatchQueue.main.async {
            onInsertionAnchorChange?(context.coordinator.insertionAnchor(in: textView))
        }
        return textView
    }

    public func updateUIView(_ uiView: UITextView, context: Context) {
        guard let textView = uiView as? MarkdownTextView else { return }
        let coordinator = context.coordinator

        textView.isEditable = isEditable
        textView.onPasteImage = onPasteImage
        #if os(iOS)
        updateInputAccessory(on: textView)
        #endif
        let imageServicesChanged = coordinator.configuration.services.images.fingerprint()
            != configuration.services.images.fingerprint()
        coordinator.configuration = configuration
        coordinator.onCaretRectChange = onCaretRectChange
        coordinator.onInlineSelectionChange = onInlineSelectionChange
        coordinator.onCodeBlockSelectionChange = onCodeBlockSelectionChange
        coordinator.onDropImages = onDropImages
        coordinator.onInsertionAnchorChange = onInsertionAnchorChange
        coordinator.onTextEditRequestCompletion = onTextEditRequestCompletion

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
            coordinator.documentGeneration += 1
            coordinator.queuedTextEditRequestID = nil
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

        let textEditRequest: MarkdownTextEditRequest?
        if let request = pendingTextEditRequest, request.documentID != documentId {
            coordinator.cancelledTextEditRequestID = request.id
            discardTextEditRequest(request, coordinator: coordinator)
            textEditRequest = nil
        } else if let request = pendingTextEditRequest,
                  coordinator.cancelledTextEditRequestID == request.id {
            clearTextEditRequest(request)
            textEditRequest = nil
        } else {
            textEditRequest = pendingTextEditRequest
        }

        if coordinator.didInitialFormatting,
           coordinator.lastSyncedText == text,
           !fontChanged,
           !isDocumentSwitch,
           !imageServicesChanged {
            if let textEditRequest {
                queueTextEditRequest(textEditRequest, textView: textView, coordinator: coordinator)
            }
            return
        }

        coordinator.rebuildTextStorageAndStyle(textView, from: text)
        coordinator.didInitialFormatting = true
        if let textEditRequest {
            queueTextEditRequest(textEditRequest, textView: textView, coordinator: coordinator)
        }
    }

    private func queueTextEditRequest(
        _ request: MarkdownTextEditRequest,
        textView: MarkdownTextView,
        coordinator: MarkdownTextViewCoordinator
    ) {
        guard coordinator.cancelledTextEditRequestID != request.id else { return }
        guard coordinator.queuedTextEditRequestID != request.id else { return }
        let documentGeneration = coordinator.documentGeneration
        coordinator.queuedTextEditRequestID = request.id
        DispatchQueue.main.async {
            defer {
                if coordinator.queuedTextEditRequestID == request.id {
                    coordinator.queuedTextEditRequestID = nil
                }
            }
            guard coordinator.documentGeneration == documentGeneration,
                  coordinator.cancelledTextEditRequestID != request.id,
                  coordinator.documentId == request.documentID,
                  self.pendingTextEditRequest?.id == request.id else {
                if coordinator.documentId != request.documentID {
                    discardTextEditRequest(request, coordinator: coordinator)
                }
                return
            }
            coordinator.apply(request, to: textView)
            completeTextEditRequest(request, result: .applied, coordinator: coordinator)
            self.pendingTextEditRequest = nil
        }
    }

    private func completeTextEditRequest(
        _ request: MarkdownTextEditRequest,
        result: MarkdownTextEditRequestResult,
        coordinator: MarkdownTextViewCoordinator
    ) {
        guard coordinator.completedTextEditRequestID != request.id else { return }
        coordinator.completedTextEditRequestID = request.id
        coordinator.onTextEditRequestCompletion?(request.id, result)
    }

    private func clearTextEditRequest(_ request: MarkdownTextEditRequest) {
        DispatchQueue.main.async {
            if self.pendingTextEditRequest?.id == request.id {
                self.pendingTextEditRequest = nil
            }
        }
    }

    private func discardTextEditRequest(
        _ request: MarkdownTextEditRequest,
        coordinator: MarkdownTextViewCoordinator
    ) {
        DispatchQueue.main.async {
            if self.pendingTextEditRequest?.id == request.id {
                self.pendingTextEditRequest = nil
            }
            completeTextEditRequest(
                request,
                result: .discardedDocumentMismatch,
                coordinator: coordinator
            )
        }
    }

    #if os(iOS)
    private func updateInputAccessory(on textView: MarkdownTextView) {
        guard let inputAccessoryContent else {
            textView.inputAccessoryView = nil
            return
        }

        let rootView = inputAccessoryContent()
        if let accessory = textView.inputAccessoryView as? MarkdownInputAccessoryHostingView {
            accessory.update(rootView: rootView)
        } else {
            textView.inputAccessoryView = MarkdownInputAccessoryHostingView(
                rootView: rootView
            )
        }
    }
    #endif

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
        ).storage)
    }

    private func installLayoutDelegate(
        on textView: MarkdownTextView,
        context: Context,
        baseFont: PlatformFont
    ) {
        let delegate = MarkdownLayoutManagerDelegate()
        delegate.renderContext = MarkdownRenderContext(
            configuration: configuration,
            baseFont: baseFont
        )
        context.coordinator.layoutDelegate = delegate
        // Setting `markdownLayoutDelegate` on the text view also re-attaches
        // the delegate to the current textLayoutManager and invalidates
        // layout. It will keep re-attaching across UITextView's
        // textLayoutManager swaps (becomeFirstResponder, resignFirstResponder,
        // move-to-window) which is what kept `\[ … \]` invisible after
        // tapping into the editor.
        textView.markdownLayoutDelegate = delegate
    }
}

#if os(iOS)
@MainActor
private final class MarkdownInputAccessoryHostingView: UIInputView {
    private let hostingController: UIHostingController<AnyView>
    private var accessoryHeight: CGFloat = 44

    init(rootView: AnyView) {
        hostingController = UIHostingController(rootView: rootView)
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        autoresizingMask = [.flexibleWidth]

        guard let hostedView = hostingController.view else { return }
        hostedView.backgroundColor = .clear
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameDidChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: accessoryHeight)
    }

    func update(rootView: AnyView) {
        hostingController.rootView = rootView
    }

    @objc private func keyboardFrameDidChange(_ notification: Notification) {
        guard let window,
              let screenFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        let keyboardFrame = window.convert(screenFrame, from: nil)
        let keyboardOverlap = max(0, window.bounds.maxY - keyboardFrame.minY)
        let newHeight: CGFloat = keyboardOverlap > 100 ? 44 : 0
        if newHeight != accessoryHeight {
            accessoryHeight = newHeight
            invalidateIntrinsicContentSize()
        }
    }
}
#endif
#endif
