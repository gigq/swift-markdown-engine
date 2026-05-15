//
//  MarkdownAttributeKeys.swift
//  MarkdownEngine
//
//  Custom NSAttributedString keys used by the styler and the Mac-only
//  layout-fragment renderer. Hoisted to a cross-platform file so the styler
//  can write these keys on iOS even though the renderer that consumes them
//  is currently macOS-only.
//

import Foundation

extension NSAttributedString.Key {
    static let latexImage = NSAttributedString.Key("LatexRenderedImage")
    static let latexBounds = NSAttributedString.Key("LatexImageBounds")
    static let latexIsBlock = NSAttributedString.Key("LatexIsBlock")
    static let latexBlockOffsetY = NSAttributedString.Key("LatexBlockOffsetY")
    /// Marks a paragraph as part of a `> ` blockquote so the layout
    /// fragment can draw a vertical rule in the left margin.
    static let blockquoteBar = NSAttributedString.Key("MarkdownBlockquoteBar")
    /// Marks the (hidden) `-` / `*` / `+` marker of an unordered list
    /// item so the layout fragment can paint a `•` bullet glyph in its
    /// place. Ordered-list numbers stay as plain text and don't get this
    /// attribute.
    static let listBullet = NSAttributedString.Key("MarkdownListBullet")
    /// Sibling of `.listBullet` that carries the original source marker
    /// character (`-`, `*`, `+`) as an `NSString`. Set on the substituted
    /// `•` glyph so the coordinator can reverse the substitution back to
    /// the source form before forwarding text to the binding.
    static let listBulletOriginal = NSAttributedString.Key("MarkdownListBulletOriginal")
    /// Marks a `---` / `***` / `___` horizontal-rule paragraph. The
    /// layout fragment paints a full-container-width line in place of
    /// the (hidden) source characters.
    static let horizontalRule = NSAttributedString.Key("MarkdownHorizontalRule")
}

#if !os(macOS)
// macOS exposes `.spellingState` natively. iOS doesn't, but the styler still
// tags ranges with this key so the Mac editor can suppress spell-checking on
// LaTeX / link content. Defining a same-name iOS shim keeps the attribute
// dictionaries cross-platform; on iOS the value is harmless metadata.
extension NSAttributedString.Key {
    static let spellingState = NSAttributedString.Key("NSSpellingState")
}
#endif
