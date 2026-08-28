import AppKit
import SwiftUI

extension NSColor {
    fileprivate convenience init(rgb: UInt32) {
        self.init(
            srgbRed: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    fileprivate static func adaptive(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        }
    }
}

/// Deezer's own Tempo tokens, adapted so they hold up in both macOS appearances.
extension Color {
    static let brand = Color(nsColor: .adaptive(light: 0xA238FF, dark: 0xB36BFF))
    static let brandStrong = Color(nsColor: .adaptive(light: 0x9333E8, dark: 0xA238FF))
    static let brandSoft = Color(nsColor: .adaptive(light: 0xF6EBFF, dark: 0x2A2135))

    static let canvas = Color(nsColor: .adaptive(light: 0xFDFCFE, dark: 0x121216))
    static let raised = Color(nsColor: .adaptive(light: 0xFFFFFF, dark: 0x191922))
    static let sunken = Color(nsColor: .adaptive(light: 0xF5F2F8, dark: 0x1E1E28))
    static let hairline = Color(nsColor: .adaptive(light: 0xE1DDE4, dark: 0x32323D))

    static let success = Color(nsColor: .adaptive(light: 0x00A038, dark: 0x2ECC63))
    static let warning = Color(nsColor: .adaptive(light: 0xEC7F11, dark: 0xF59A3C))
    static let failure = Color(nsColor: .adaptive(light: 0xDF3C3C, dark: 0xFF6B6B))
}

extension ShapeStyle where Self == Color {
    static var brand: Color { .brand }
    static var brandStrong: Color { .brandStrong }
    static var success: Color { .success }
    static var warning: Color { .warning }
    static var failure: Color { .failure }
}

enum Metrics {
    static let cornerRadius: CGFloat = 10
    static let cardCorner: CGFloat = 12
    static let artworkCorner: CGFloat = 8
    static let rowHeight: CGFloat = 38
    static let gutter: CGFloat = 28
    static let cardGap: CGFloat = 18
    /// The inset list style already indents its rows; this tops them up to the page gutter.
    static let listGutter: CGFloat = 18
}
