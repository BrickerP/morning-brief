import SwiftUI

/// Central design system for the brief panel. Keeping colors, spacing, radii and
/// type in one place lets every view read from the same scale instead of
/// scattering magic numbers, and gives a single seam for future theming.
enum DS {
    // MARK: Spacing scale (4pt base)
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
    }

    // MARK: Corner radii
    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
    }

    // MARK: Semantic colors (adapt to light/dark via system materials)
    enum Palette {
        static let cardFill = Color(nsColor: .controlBackgroundColor)
        static let cardStroke = Color.primary.opacity(0.08)
        static let quoteBar = Color.accentColor.opacity(0.55)
        static let quoteFill = Color.accentColor.opacity(0.06)
        static let bullet = Color.accentColor.opacity(0.7)
        static let subtle = Color.primary.opacity(0.55)
    }

    // MARK: Type ramp
    enum Typo {
        static let sectionTitle = SwiftUI.Font.headline
        static let h1 = SwiftUI.Font.title3.weight(.bold)
        static let h2 = SwiftUI.Font.headline
        static let h3 = SwiftUI.Font.subheadline.weight(.semibold)
        static let body = SwiftUI.Font.callout
        static let quote = SwiftUI.Font.callout.italic()
        static let caption = SwiftUI.Font.caption
    }
}

/// Kind → accent color + SF Symbol, so each section reads at a glance.
struct SectionStyle {
    let symbol: String
    let tint: Color

    static func forKind(_ kind: String) -> SectionStyle {
        switch kind.lowercased() {
        case "news": SectionStyle(symbol: "bolt.fill", tint: .orange)
        case "digest": SectionStyle(symbol: "book.fill", tint: .blue)
        case "essay": SectionStyle(symbol: "text.quote", tint: .purple)
        case "events": SectionStyle(symbol: "calendar", tint: .green)
        case "tools": SectionStyle(symbol: "wrench.and.screwdriver.fill", tint: .teal)
        default: SectionStyle(symbol: "doc.text", tint: .secondary)
        }
    }
}
