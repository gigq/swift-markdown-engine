//
//  PlatformTypes.swift
//  MarkdownEngine
//
//  Cross-platform typealiases. The Mac-only editor stack keeps using
//  `NSFont`/`NSColor`/`NSView` directly under `#if os(macOS)` guards; the
//  shared parser, styler, configuration, and renderer use the `Platform*`
//  aliases so they compile on both macOS and iOS.
//

#if canImport(AppKit)
import AppKit

public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
public typealias PlatformFontDescriptor = NSFontDescriptor
public typealias PlatformImage = NSImage
public typealias PlatformBezierPath = NSBezierPath
public typealias PlatformEdgeInsets = NSEdgeInsets
#elseif canImport(UIKit)
import UIKit

public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
public typealias PlatformFontDescriptor = UIFontDescriptor
public typealias PlatformImage = UIImage
public typealias PlatformBezierPath = UIBezierPath
public typealias PlatformEdgeInsets = UIEdgeInsets
#endif

public enum PlatformSemanticColors {
    public static var label: PlatformColor {
        #if canImport(AppKit)
        return .labelColor
        #else
        return .label
        #endif
    }

    public static var secondaryLabel: PlatformColor {
        #if canImport(AppKit)
        return .secondaryLabelColor
        #else
        return .secondaryLabel
        #endif
    }

    public static var tertiaryLabel: PlatformColor {
        #if canImport(AppKit)
        return .tertiaryLabelColor
        #else
        return .tertiaryLabel
        #endif
    }

    public static var link: PlatformColor {
        #if canImport(AppKit)
        return .linkColor
        #else
        return .link
        #endif
    }
}

enum PlatformFontMaker {
    static func make(name: String, size: CGFloat) -> PlatformFont {
        PlatformFont(name: name, size: size) ?? PlatformFont.systemFont(ofSize: size)
    }

    static func bold(_ font: PlatformFont) -> PlatformFont {
        #if canImport(AppKit)
        if let desc = font.fontDescriptor.withSymbolicTraits(.bold) as NSFontDescriptor?,
           let bolded = NSFont(descriptor: desc, size: font.pointSize) {
            return bolded
        }
        return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        #else
        if let desc = font.fontDescriptor.withSymbolicTraits(.traitBold) {
            return UIFont(descriptor: desc, size: font.pointSize)
        }
        return font
        #endif
    }

    static func italic(_ font: PlatformFont) -> PlatformFont {
        #if canImport(AppKit)
        if let desc = font.fontDescriptor.withSymbolicTraits(.italic) as NSFontDescriptor?,
           let italicized = NSFont(descriptor: desc, size: font.pointSize) {
            return italicized
        }
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        #else
        if let desc = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
            return UIFont(descriptor: desc, size: font.pointSize)
        }
        return font
        #endif
    }

    static func boldItalic(_ font: PlatformFont) -> PlatformFont {
        #if canImport(AppKit)
        if let desc = font.fontDescriptor.withSymbolicTraits([.bold, .italic]) as NSFontDescriptor?,
           let result = NSFont(descriptor: desc, size: font.pointSize) {
            return result
        }
        return NSFontManager.shared.convert(font, toHaveTrait: [.boldFontMask, .italicFontMask])
        #else
        if let desc = font.fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) {
            return UIFont(descriptor: desc, size: font.pointSize)
        }
        return font
        #endif
    }

    static func bold(name: String, size: CGFloat) -> PlatformFont {
        bold(make(name: name, size: size))
    }
}

extension NSValue {
    /// Cross-platform CGRect wrapping. AppKit ships `init(rect:)` (NSRect ≡ CGRect),
    /// UIKit ships `init(cgRect:)`; this picks the right one.
    static func cgRectValue(_ rect: CGRect) -> NSValue {
        #if os(macOS)
        return NSValue(rect: rect)
        #else
        return NSValue(cgRect: rect)
        #endif
    }
}
