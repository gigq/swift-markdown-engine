#if os(macOS)
//
//  NativeTextView+TaskCheckbox.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 16.03.26.
//
//  Hit-test for `[ ]` / `[x]` checkbox glyphs and toggle the underlying text
//  + `.taskCheckbox` attribute, then nudge the coordinator to restyle the
//  enclosing paragraph.
//

import AppKit

extension NativeTextView {
    func activateImageEmbedIfHit(event: NSEvent) -> Bool {
        guard event.clickCount == 1,
              !event.modifierFlags.contains(.option),
              let textContainer,
              let bridge = layoutBridge,
              let storage = textStorage else { return false }
        let localPoint = convert(event.locationInWindow, from: nil)
        let containerPoint = CGPoint(
            x: localPoint.x - textContainerOrigin.x,
            y: localPoint.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let index = bridge.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        guard index != NSNotFound,
              index < storage.length,
              let rawContent = storage.attribute(
                  .imageEmbedReference,
                  at: index,
                  effectiveRange: nil
              ) as? String,
              let reference = ImageEmbedReference(content: rawContent),
              let coordinator = delegate as? NativeTextViewCoordinator,
              let onImageEmbedClick = coordinator.onImageEmbedClick else { return false }
        onImageEmbedClick(reference.providerRequest)
        return true
    }

    func updateImageEmbedAccessibilityActions(
        onActivate: ((EmbeddedImageRequest) -> Void)?
    ) {
        guard let onActivate else {
            setAccessibilityCustomActions(nil)
            return
        }
        var references: [ImageEmbedReference] = []
        textStorage?.enumerateAttribute(
            .imageEmbedReference,
            in: NSRange(location: 0, length: textStorage?.length ?? 0)
        ) { value, _, _ in
            guard let rawContent = value as? String,
                  let reference = ImageEmbedReference(content: rawContent) else { return }
            references.append(reference)
        }
        let actions = references.map { reference in
            NSAccessibilityCustomAction(name: "Preview \(reference.name)") {
                onActivate(reference.providerRequest)
                return true
            }
        }
        setAccessibilityCustomActions(actions)
    }

    func toggleTaskCheckboxIfHit(event: NSEvent) -> Bool? {
        guard let textContainer = textContainer,
              let bridge = layoutBridge,
              let storage = textStorage else { return nil }
        let localPoint = convert(event.locationInWindow, from: nil)
        let containerPoint = CGPoint(
            x: localPoint.x - textContainerOrigin.x,
            y: localPoint.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let index = bridge.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        guard index != NSNotFound, index < storage.length else { return nil }

        var effectiveRange = NSRange(location: 0, length: 0)
        guard let isChecked = storage.attribute(.taskCheckbox, at: index, effectiveRange: &effectiveRange) as? Bool,
              effectiveRange.length > 0 else { return nil }

        let nsText = storage.string as NSString
        let checkboxText = nsText.substring(with: effectiveRange)
        guard checkboxText.range(of: #"\[[ xX]\]"#, options: .regularExpression) != nil else { return nil }

        let replacement = isChecked ? "[ ]" : "[x]"
        if shouldChangeText(in: effectiveRange, replacementString: replacement) {
            storage.replaceCharacters(in: effectiveRange, with: replacement)
            storage.addAttribute(.taskCheckbox, value: !isChecked, range: effectiveRange)
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: effectiveRange)
            didChangeText()
            bridge.invalidateDisplay(forCharacterRange: effectiveRange)
            if let coord = delegate as? NativeTextViewCoordinator {
                let paragraph = (storage.string as NSString).paragraphRange(for: effectiveRange)
                coord.restyleParagraphs([paragraph], in: self)
            }
        }
        return true
    }
}

#endif
