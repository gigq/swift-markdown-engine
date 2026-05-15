//
//  MarkdownTextView+TaskCheckbox.swift
//  MarkdownEngine
//
//  Lets users tap a `[ ]` / `[x]` glyph to toggle its completion state.
//  Mirrors the Mac `NativeTextView+TaskCheckbox` mouse-click handling but
//  goes through a `UITapGestureRecognizer` that runs alongside UITextView's
//  built-in tap handling.
//

#if os(iOS) || os(visionOS)
import UIKit

extension MarkdownTextView {
    func installCheckboxTapHandler() {
        guard checkboxTapGesture == nil else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleCheckboxTap(_:)))
        tap.cancelsTouchesInView = false
        // Run before UITextView's own taps so we get a chance to toggle.
        tap.delegate = nil
        addGestureRecognizer(tap)
        checkboxTapGesture = tap
    }

    @objc private func handleCheckboxTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let location = recognizer.location(in: self)
        let storage = textStorage
        guard storage.length > 0 else { return }

        // Convert tap location into the textContainer's coordinate space.
        let inset = textContainerInset
        let containerPoint = CGPoint(x: location.x - inset.left, y: location.y - inset.top)

        // TextKit 2 path — preferred since the rest of the renderer runs on it.
        if let textLayoutManager = textLayoutManager,
           let fragment = textLayoutManager.textLayoutFragment(for: containerPoint),
           let charIndex = characterIndex(at: containerPoint, fragment: fragment) {
            if toggleCheckbox(at: charIndex) { return }
        }

        // Fallback to the TextKit 1 layout manager (UITextView keeps one
        // available for legacy compatibility even when `usingTextLayoutManager`
        // was true).
        let lm = layoutManager
        let container = textContainer
        let glyphIndex = lm.glyphIndex(for: containerPoint, in: container)
        let charIndex = lm.characterIndexForGlyph(at: glyphIndex)
        _ = toggleCheckbox(at: charIndex)
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

    private var checkboxTapGesture: UITapGestureRecognizer? {
        get { objc_getAssociatedObject(self, &checkboxTapGestureKey) as? UITapGestureRecognizer }
        set { objc_setAssociatedObject(self, &checkboxTapGestureKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

private nonisolated(unsafe) var checkboxTapGestureKey: UInt8 = 0
#endif
