//
//  CheckboxAttachment.swift
//  MarkdownEngine
//
//  NSTextAttachment that renders a task-checkbox SF Symbol in place of the
//  `-` marker of a GFM task-list line. Mirrors `LatexImageAttachment` —
//  attachments survive UITextView's mid-edit `textLayoutManager` swaps on
//  iOS 26, where the custom `MarkdownTextLayoutFragment` drawing path
//  silently stops running and blanks the checkbox glyph.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation

final class CheckboxAttachment: NSTextAttachment, AnchorSubstituteAttachment {
    private let renderedBounds: CGRect

    /// Always the original marker character (typically `-`). The coordinator
    /// restores it before piping text back to the binding so the binding
    /// never sees a stray U+FFFC.
    let originalChar: Character

    /// Toggled by tap-to-complete; lets the styler emit a fresh attachment
    /// with the right SF Symbol on the next restyle pass.
    let isChecked: Bool

    init(image: PlatformImage, bounds: CGRect, originalChar: Character, isChecked: Bool) {
        self.renderedBounds = bounds
        self.originalChar = originalChar
        self.isChecked = isChecked
        super.init(data: nil, ofType: nil)
        self.image = image
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        renderedBounds
    }
}
