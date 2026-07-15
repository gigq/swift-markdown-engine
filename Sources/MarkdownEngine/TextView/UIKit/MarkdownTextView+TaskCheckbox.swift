//
//  MarkdownTextView+TaskCheckbox.swift
//  MarkdownEngine
//
//  Lets users tap a `[ ]` / `[x]` glyph to toggle its completion state.
//  Mirrors the Mac `NativeTextView+TaskCheckbox` mouse-click handling but
//  goes through a `UITapGestureRecognizer` that runs alongside UITextView's
//  built-in tap-to-position-caret recognizer.
//

#if os(iOS) || os(visionOS)
import UIKit

extension MarkdownTextView {
    func installImageEmbedTapHandler() {
        guard imageEmbedTapGesture == nil else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleImageEmbedTap(_:)))
        tap.cancelsTouchesInView = false
        let delegate = ImageEmbedTapDelegate(textView: self)
        tap.delegate = delegate
        imageEmbedTapDelegate = delegate
        addGestureRecognizer(tap)
        imageEmbedTapGesture = tap
    }

    func updateImageEmbedAccessibilityActions(
        onActivate: ((EmbeddedImageRequest) -> Void)?
    ) {
        guard let onActivate else {
            accessibilityCustomActions = nil
            return
        }
        var references: [ImageEmbedReference] = []
        textStorage.enumerateAttribute(
            .imageEmbedReference,
            in: NSRange(location: 0, length: textStorage.length)
        ) { value, _, _ in
            guard let rawContent = value as? String,
                  let reference = ImageEmbedReference(content: rawContent) else { return }
            references.append(reference)
        }
        accessibilityCustomActions = references.map { reference in
            UIAccessibilityCustomAction(name: "Preview \(reference.name)") { _ in
                onActivate(reference.providerRequest)
                return true
            }
        }
    }

    func installCheckboxTapHandler() {
        guard checkboxTapGesture == nil else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleCheckboxTap(_:)))
        tap.cancelsTouchesInView = false
        // Filter via a delegate so we *only* recognize taps that land inside
        // a checkbox glyph; every other tap stays with UITextView's
        // caret-positioning recognizer. Without this, the tap recognizer
        // monopolized all taps and the keyboard never showed up.
        let delegate = CheckboxTapDelegate(textView: self)
        tap.delegate = delegate
        checkboxTapDelegate = delegate
        addGestureRecognizer(tap)
        checkboxTapGesture = tap
    }

    @objc fileprivate func handleCheckboxTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let location = recognizer.location(in: self)
        guard let charIndex = characterIndexForTap(at: location) else { return }
        _ = toggleCheckbox(at: charIndex)
    }

    @objc fileprivate func handleImageEmbedTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let location = recognizer.location(in: self)
        guard let charIndex = characterIndexForTap(at: location),
              charIndex >= 0,
              charIndex < textStorage.length,
              let rawContent = textStorage.attribute(
                  .imageEmbedReference,
                  at: charIndex,
                  effectiveRange: nil
              ) as? String,
              let reference = ImageEmbedReference(content: rawContent),
              let coordinator = delegate as? MarkdownTextViewCoordinator else { return }
        coordinator.onImageEmbedClick?(reference.providerRequest)
    }

    /// Hit-test helper — returns the document character index under a tap,
    /// or nil if the tap missed all glyphs. Used both by the tap gesture's
    /// `should-begin` filter and by the actual toggle handler.
    fileprivate func characterIndexForTap(at location: CGPoint) -> Int? {
        let inset = textContainerInset
        let containerPoint = CGPoint(x: location.x - inset.left, y: location.y - inset.top)

        if let textLayoutManager = textLayoutManager,
           let fragment = textLayoutManager.textLayoutFragment(for: containerPoint),
           let charIndex = characterIndex(at: containerPoint, fragment: fragment) {
            return charIndex
        }

        // Fallback to the TextKit 1 layout manager.
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }

    fileprivate func tapLandsOnCheckbox(at location: CGPoint) -> Bool {
        guard let charIndex = characterIndexForTap(at: location),
              charIndex >= 0,
              charIndex < textStorage.length else { return false }
        return textStorage.attribute(.taskCheckbox, at: charIndex, effectiveRange: nil) != nil
    }

    fileprivate func tapLandsOnImageEmbed(at location: CGPoint) -> Bool {
        guard let charIndex = characterIndexForTap(at: location),
              charIndex >= 0,
              charIndex < textStorage.length,
              let coordinator = delegate as? MarkdownTextViewCoordinator,
              coordinator.onImageEmbedClick != nil else { return false }
        return textStorage.attribute(.imageEmbedReference, at: charIndex, effectiveRange: nil) != nil
    }

    private func characterIndex(at containerPoint: CGPoint, fragment: NSTextLayoutFragment) -> Int? {
        guard let tcs = textLayoutManager?.textContentManager as? NSTextContentStorage else { return nil }
        let fragFrame = fragment.layoutFragmentFrame
        let localPoint = CGPoint(x: containerPoint.x - fragFrame.origin.x,
                                 y: containerPoint.y - fragFrame.origin.y)
        var lineY: CGFloat = 0
        for lineFragment in fragment.textLineFragments {
            let bounds = lineFragment.typographicBounds
            if localPoint.y < lineY + bounds.height || lineFragment === fragment.textLineFragments.last {
                let lineLocal = CGPoint(x: localPoint.x - lineFragment.glyphOrigin.x,
                                        y: localPoint.y - lineY)
                let charInLine = lineFragment.characterIndex(for: lineLocal)
                let fragmentStart = tcs.offset(
                    from: tcs.documentRange.location,
                    to: fragment.rangeInElement.location
                )
                return fragmentStart + lineFragment.characterRange.location + charInLine
            }
            lineY += bounds.height
        }
        return nil
    }

    /// Returns true if the tap landed inside a task-checkbox range and the
    /// state was toggled; false if it wasn't a checkbox.
    @discardableResult
    private func toggleCheckbox(at index: Int) -> Bool {
        let storage = textStorage
        guard index >= 0, index < storage.length else { return false }

        var effectiveRange = NSRange(location: NSNotFound, length: 0)
        guard let isChecked = storage.attribute(.taskCheckbox, at: index, effectiveRange: &effectiveRange) as? Bool,
              effectiveRange.location != NSNotFound else {
            return false
        }

        // Replace the literal marker text `[ ]` ↔ `[x]` so the source stays in sync.
        let lineRange = (storage.string as NSString).lineRange(for: effectiveRange)
        let line = (storage.string as NSString).substring(with: lineRange) as NSString
        let openIdx = line.range(of: "[", options: .literal).location
        guard openIdx != NSNotFound else { return false }
        let bracketStart = lineRange.location + openIdx
        let bracketContentRange = NSRange(location: bracketStart + 1, length: 1)
        guard bracketContentRange.location + bracketContentRange.length <= storage.length else { return false }

        let replacement = isChecked ? " " : "x"
        isPerformingProgrammaticEdit = true
        storage.replaceCharacters(in: bracketContentRange, with: replacement)
        storage.addAttribute(.taskCheckbox, value: !isChecked, range: effectiveRange)
        isPerformingProgrammaticEdit = false

        // Drive the standard change cycle so the binding + restyle pick up the new state.
        if let coord = delegate as? MarkdownTextViewCoordinator {
            coord.textViewDidChange(self)
        }
        return true
    }

    fileprivate var checkboxTapGesture: UITapGestureRecognizer? {
        get { objc_getAssociatedObject(self, &checkboxTapGestureKey) as? UITapGestureRecognizer }
        set { objc_setAssociatedObject(self, &checkboxTapGestureKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    fileprivate var checkboxTapDelegate: CheckboxTapDelegate? {
        get { objc_getAssociatedObject(self, &checkboxTapDelegateKey) as? CheckboxTapDelegate }
        set { objc_setAssociatedObject(self, &checkboxTapDelegateKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    fileprivate var imageEmbedTapGesture: UITapGestureRecognizer? {
        get { objc_getAssociatedObject(self, &imageEmbedTapGestureKey) as? UITapGestureRecognizer }
        set { objc_setAssociatedObject(self, &imageEmbedTapGestureKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    fileprivate var imageEmbedTapDelegate: ImageEmbedTapDelegate? {
        get { objc_getAssociatedObject(self, &imageEmbedTapDelegateKey) as? ImageEmbedTapDelegate }
        set { objc_setAssociatedObject(self, &imageEmbedTapDelegateKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

/// Side-object delegate so we can filter the checkbox tap without
/// `MarkdownTextView` having to claim conformance to
/// `UIGestureRecognizerDelegate` (which would conflict with UITextView's
/// own scroll-view-level conformance).
private final class CheckboxTapDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var textView: MarkdownTextView?

    init(textView: MarkdownTextView) {
        self.textView = textView
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let textView else { return false }
        let location = gestureRecognizer.location(in: textView)
        return textView.tapLandsOnCheckbox(at: location)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Run alongside UITextView's own taps so caret positioning continues
        // to work for non-checkbox taps.
        true
    }
}

private final class ImageEmbedTapDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var textView: MarkdownTextView?

    init(textView: MarkdownTextView) {
        self.textView = textView
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let textView else { return false }
        return textView.tapLandsOnImageEmbed(at: gestureRecognizer.location(in: textView))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

private nonisolated(unsafe) var checkboxTapGestureKey: UInt8 = 0
private nonisolated(unsafe) var checkboxTapDelegateKey: UInt8 = 0
private nonisolated(unsafe) var imageEmbedTapGestureKey: UInt8 = 0
private nonisolated(unsafe) var imageEmbedTapDelegateKey: UInt8 = 0
#endif
