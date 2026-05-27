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

    /// Cross-platform unwrap. AppKit reads it back as `rectValue`,
    /// UIKit as `cgRectValue`.
    var cgRectValueCross: CGRect {
        #if os(macOS)
        return rectValue
        #else
        return cgRectValue
        #endif
    }
}

extension PlatformColor {
    /// Cross-platform RGB(A) component extraction. Returns nil if the color
    /// can't be converted to a calibrated RGB space.
    public func rgbComponents() -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        #if canImport(AppKit)
        guard let rgb = usingColorSpace(.deviceRGB) else { return nil }
        return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent)
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (r, g, b, a)
        #endif
    }
}

/// Drawing helpers that wrap the AppKit `NSGraphicsContext` / UIKit
/// `UIGraphicsPushContext` push-pop dance so the rest of the renderer can
/// stay platform-agnostic.
enum PlatformGraphics {
    /// Push `context` as current for the duration of `block`, treating coordinates
    /// as flipped (top-left origin) on both platforms. AppKit needs an explicit
    /// `NSGraphicsContext(cgContext:flipped:)`; UIKit always uses the active CG
    /// context and is already top-left flipped.
    static func withFlippedContext(_ context: CGContext, _ block: () -> Void) {
        #if canImport(AppKit)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        block()
        #else
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        block()
        #endif
    }
}

extension PlatformBezierPath {
    /// AppKit's `NSBezierPath` has `appendRect(_:)`; UIKit's `UIBezierPath`
    /// uses `append(UIBezierPath(rect:))`. Single name on both.
    func appendCrossPlatform(rect: CGRect) {
        #if canImport(AppKit)
        appendRect(rect)
        #else
        append(UIBezierPath(rect: rect))
        #endif
    }

    /// `NSBezierPath.windingRule = .evenOdd` vs
    /// `UIBezierPath.usesEvenOddFillRule = true`.
    func setEvenOddFillRule() {
        #if canImport(AppKit)
        windingRule = .evenOdd
        #else
        usesEvenOddFillRule = true
        #endif
    }
}

extension PlatformImage {
    /// Cross-platform SF Symbol lookup. AppKit takes `accessibilityDescription:`,
    /// UIKit takes a `withConfiguration:` parameter for size/weight.
    static func systemSymbol(name: String) -> PlatformImage? {
        #if canImport(AppKit)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)
        #else
        return UIImage(systemName: name)
        #endif
    }

    /// SF Symbol with an explicit point size and hierarchical tint color, regular
    /// weight. Returns nil if the symbol name is unknown.
    static func systemSymbol(
        name: String,
        pointSize: CGFloat,
        hierarchicalTint: PlatformColor
    ) -> PlatformImage? {
        #if canImport(AppKit)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        let sizeConfig = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let colorConfig = NSImage.SymbolConfiguration(hierarchicalColor: hierarchicalTint)
        return base.withSymbolConfiguration(sizeConfig.applying(colorConfig)) ?? base
        #else
        guard let base = UIImage(systemName: name) else { return nil }
        let sizeConfig = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let colorConfig = UIImage.SymbolConfiguration(hierarchicalColor: hierarchicalTint)
        let combined = sizeConfig.applying(colorConfig)
        return base.applyingSymbolConfiguration(combined) ?? base
        #endif
    }
}

enum PlatformScale {
    /// Best-effort device pixel scale. Falls back to 2.0 (Retina) when
    /// neither the view nor a main screen is reachable.
    static func backingScale(for textView: AnyObject?) -> CGFloat {
        #if canImport(AppKit)
        if let tv = textView as? NSView,
           let scale = tv.window?.backingScaleFactor {
            return scale
        }
        return NSScreen.main?.backingScaleFactor ?? 2.0
        #else
        #if os(visionOS)
        if let tv = textView as? UIView,
           tv.traitCollection.displayScale > 0 {
            return tv.traitCollection.displayScale
        }
        return 2.0
        #else
        if let tv = textView as? UIView,
           let scale = tv.window?.screen.scale {
            return scale
        }
        return UIScreen.main.scale
        #endif
        #endif
    }
}
