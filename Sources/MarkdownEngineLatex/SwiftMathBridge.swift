//
//  SwiftMathBridge.swift
//  MarkdownEngineLatex
//
//  Ready-made LatexRenderer conformance backed by SwiftMath. Cross-platform:
//  generates either an `NSImage` (macOS) or a `UIImage` (iOS / iPadOS /
//  visionOS) via SwiftMath's `MathImage.asImage()`.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation
import SwiftMath
import MarkdownEngine

/// A drop-in ``LatexRenderer`` backed by [SwiftMath].
///
/// Renders both block (`$$ … $$`) and inline (`$ … $`) LaTeX strings into
/// `PlatformImage`s using the Latin Modern math font. Results are cached
/// per (latex, font size, appearance, theme color fingerprint) so repeated
/// renders are free.
///
/// Light/dark appearance is taken from the active window's trait collection
/// (UIKit) or effective appearance (AppKit), so apps that force a light
/// window when the system is in dark mode still get correctly-tinted
/// formulas.
///
/// [SwiftMath]: https://github.com/mgriebling/SwiftMath
public final class SwiftMathBridge: LatexRenderer, @unchecked Sendable {
    private struct CacheKey: Hashable {
        let latex: String
        let fontSize: CGFloat
        let isDarkMode: Bool
        let lightColorRGB: UInt32
        let darkColorRGB: UInt32
    }

    private struct CacheEntry {
        let image: PlatformImage
        let size: CGSize
        let baselineOffset: CGFloat
    }

    private let singleLetterPaddingBottom: CGFloat
    private var cache: [CacheKey: CacheEntry] = [:]
    private let cacheLock = NSLock()

    /// - Parameter singleLetterPaddingBottom: Extra bottom padding (in
    ///   points) added to single-letter formulas to prevent visual
    ///   clipping; matches the engine's
    ///   ``MarkdownEditorConfiguration/blockLatex/singleLetterPaddingBottom``
    ///   default. Override to match a customized configuration.
    public init(singleLetterPaddingBottom: CGFloat = 1.0) {
        self.singleLetterPaddingBottom = singleLetterPaddingBottom
    }

    /// Clears the rendered-image cache. Call after appearance flips if
    /// the host code doesn't re-render formulas automatically.
    public func clearCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }

    // MARK: - LatexRenderer

    public func render(
        latex: String,
        fontSize: CGFloat,
        theme: MarkdownEditorTheme
    ) -> LatexRenderResult? {
        let normalizedLatex = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLatex.isEmpty else { return nil }

        let isDarkMode = Self.isDarkAppearance()
        let textColor = isDarkMode ? theme.latexDarkModeText : theme.latexLightModeText
        let key = CacheKey(
            latex: normalizedLatex,
            fontSize: fontSize,
            isDarkMode: isDarkMode,
            lightColorRGB: Self.colorFingerprint(theme.latexLightModeText),
            darkColorRGB: Self.colorFingerprint(theme.latexDarkModeText)
        )

        cacheLock.lock()
        if let cached = cache[key] {
            cacheLock.unlock()
            return LatexRenderResult(
                image: cached.image,
                size: cached.size,
                baselineOffset: cached.baselineOffset
            )
        }
        cacheLock.unlock()

        guard let entry = renderLatex(normalizedLatex, fontSize: fontSize, textColor: textColor) else {
            return nil
        }

        cacheLock.lock()
        cache[key] = entry
        cacheLock.unlock()

        return LatexRenderResult(
            image: entry.image,
            size: entry.size,
            baselineOffset: entry.baselineOffset
        )
    }

    // MARK: - Private

    private static func isDarkAppearance() -> Bool {
        #if canImport(AppKit)
        let appearance = NSApp.keyWindow?.effectiveAppearance ?? NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        #else
        // Read from any connected window scene's trait collection. Falls back
        // to the global `UITraitCollection.current` (which iOS keeps in sync
        // with the foreground scene) when no scene is reachable yet.
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            return scene.traitCollection.userInterfaceStyle == .dark
        }
        return UITraitCollection.current.userInterfaceStyle == .dark
        #endif
    }

    /// Fold the LaTeX text color to a 24-bit fingerprint that's good enough
    /// to bust the cache when the theme changes the LaTeX text color.
    private static func colorFingerprint(_ color: PlatformColor) -> UInt32 {
        guard let rgb = color.rgbComponents() else { return 0 }
        let r = UInt32(max(0, min(255, Int(rgb.red * 255))))
        let g = UInt32(max(0, min(255, Int(rgb.green * 255))))
        let b = UInt32(max(0, min(255, Int(rgb.blue * 255))))
        return (r << 16) | (g << 8) | b
    }

    private func renderLatex(_ latex: String, fontSize: CGFloat, textColor: PlatformColor) -> CacheEntry? {
        let isSimpleSingleLetter = latex.range(of: #"^[A-Za-z]{1,3}$"#, options: .regularExpression) != nil
        let paddingBottom: CGFloat = isSimpleSingleLetter ? singleLetterPaddingBottom : 0

        var mathImage = MathImage(
            latex: latex,
            fontSize: fontSize,
            textColor: textColor,
            labelMode: .text,
            textAlignment: .left
        )
        if paddingBottom > 0 {
            #if canImport(AppKit)
            mathImage.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: paddingBottom, right: 0)
            #else
            mathImage.contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: paddingBottom, right: 0)
            #endif
        }

        let (error, image, layout) = mathImage.asImage()
        guard error == nil, let image, let layout else { return nil }

        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        return CacheEntry(
            image: image,
            size: size,
            baselineOffset: layout.descent
        )
    }
}
