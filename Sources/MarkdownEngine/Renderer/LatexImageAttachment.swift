//
//  LatexImageAttachment.swift
//  MarkdownEngine
//
//  NSTextAttachment carrying a SwiftMath-rendered image plus the bounds
//  TextKit should use to lay it out. We migrate LaTeX rendering off the
//  custom `MarkdownTextLayoutFragment.drawLatexImages` path because
//  UITextView on iOS 26 swaps its `textLayoutManager` mid-edit, orphaning
//  the layout-fragment delegate and silently dropping every custom
//  decoration. NSTextAttachment lives on the attributed-string side, so
//  it survives every layout-manager swap.
//
//  For TextKit 2 to actually render the attachment image, the anchor
//  character must be U+FFFC (OBJECT REPLACEMENT CHARACTER). Applying
//  `.attachment` to an arbitrary source character is silently ignored on
//  iOS 26 (TextKit just draws the source glyph). So we substitute the
//  anchor character with U+FFFC in the display storage; `originalChar`
//  remembers what was there so the coordinator can restore it before
//  the text is piped back to the binding.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation

final class LatexImageAttachment: NSTextAttachment {
    private let renderedBounds: CGRect

    /// The source character we substituted with U+FFFC at this position.
    /// `MarkdownTextViewCoordinator.textViewDidChange` reverses the
    /// substitution before forwarding the storage form to the binding.
    let originalChar: Character

    init(image: PlatformImage, bounds: CGRect, originalChar: Character) {
        self.renderedBounds = bounds
        self.originalChar = originalChar
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

extension LatexImageAttachment {
    /// U+FFFC (OBJECT REPLACEMENT CHARACTER). Standalone constant so
    /// callers don't have to import the unicode scalar.
    static let anchorCharacter: Character = "\u{FFFC}"
    static let anchorString: String = "\u{FFFC}"
}
