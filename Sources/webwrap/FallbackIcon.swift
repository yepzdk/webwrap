import Foundation
import AppKit

/// Generates a fallback app icon for the (common) case where a site exposes no usable
/// icon of its own — every source in `IconResolver`'s chain came up empty, or the app is
/// handler-only with no site at all. Rather than shipping a bundle with no icon (which
/// leaves macOS drawing its generic default-app placeholder), we draw a recognizable
/// square: a solid backdrop in the app's resolved theme/background color with the app's
/// initial as a centered monogram, colored for contrast.
///
/// Following the repo's split for the one other family of AppKit code (`Host`), the
/// color / monogram / contrast decisions are kept as pure, unit-tested statics, and the
/// single impure piece — the bitmap drawing + PNG encoding — is thin and verified by
/// hand (it runs on the macOS CI runner as a smoke test).
enum FallbackIcon {
    /// The backdrop color used when the app has no known (or an unparseable) background
    /// color: a calm neutral slate that reads well behind either black or white text.
    static let neutralDefault = CSSColor.RGBA(
        red: 0x4a / 255.0, green: 0x55 / 255.0, blue: 0x68 / 255.0, alpha: 1.0)

    /// The opaque fill for the icon backdrop. Parses the app's background color string
    /// (via the same `CSSColor` parser the host uses), falling back to `neutralDefault`
    /// when it's nil, unparseable, or fully transparent — an icon needs a solid backdrop,
    /// so any alpha is dropped.
    static func fillColor(background: String?) -> CSSColor.RGBA {
        guard let background, let rgba = CSSColor.parse(background), rgba.alpha > 0 else {
            return neutralDefault
        }
        return CSSColor.RGBA(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: 1.0)
    }

    /// The monogram to draw: the first alphanumeric character of the name, uppercased.
    /// Names with no alphanumeric character (empty, or all symbols/whitespace) fall back
    /// to "W" (for webwrap) so the icon is never blank.
    static func monogram(for name: String) -> String {
        for ch in name where ch.isLetter || ch.isNumber {
            return String(ch).uppercased()
        }
        return "W"
    }

    /// Whether dark (black) text should be drawn on the given backdrop for contrast.
    /// Light backdrops → dark text (true); dark backdrops → light/white text (false).
    /// Uses the WCAG relative-luminance formula with a 0.5 midpoint threshold.
    static func prefersDarkText(on color: CSSColor.RGBA) -> Bool {
        relativeLuminance(of: color) > 0.5
    }

    /// WCAG relative luminance (0...1) of an sRGB color: linearize each channel, then
    /// weight by the standard coefficients. Pure; drives the text-color contrast choice.
    static func relativeLuminance(of color: CSSColor.RGBA) -> Double {
        func linearize(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(color.red)
            + 0.7152 * linearize(color.green)
            + 0.0722 * linearize(color.blue)
    }

    /// Draws the fallback icon and returns PNG bytes suitable for the existing
    /// `sips`/`iconutil` `.icns` pipeline, or nil if a bitmap context can't be made.
    /// Impure (AppKit drawing); the decisions it composes are all pure statics above.
    static func pngData(background: String?, name: String, size: Int = 1024) -> Data? {
        let fill = fillColor(background: background)
        let letter = monogram(for: name)
        let textColor: NSColor = prefersDarkText(on: fill) ? .black : .white

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = NSSize(width: size, height: size)

        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = ctx
        defer { NSGraphicsContext.current = previous }

        let bounds = NSRect(x: 0, y: 0, width: size, height: size)
        NSColor(srgbRed: CGFloat(fill.red), green: CGFloat(fill.green),
                blue: CGFloat(fill.blue), alpha: 1.0).setFill()
        bounds.fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let font = NSFont.systemFont(ofSize: CGFloat(size) * 0.55, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph,
        ]
        let text = NSAttributedString(string: letter, attributes: attributes)
        let textSize = text.size()
        let textRect = NSRect(
            x: (CGFloat(size) - textSize.width) / 2,
            y: (CGFloat(size) - textSize.height) / 2,
            width: textSize.width, height: textSize.height)
        text.draw(in: textRect)

        ctx.flushGraphics()
        return rep.representation(using: .png, properties: [:])
    }
}
