import SwiftUI

/// Luminare / Loop–aligned chrome tokens.
/// Real Luminare SPM needs full Xcode (SwiftUIMacros); hand-rolled until then.
enum AppChrome {
    static let sidebarWidth: CGFloat = 188
    static let accent = Color(red: 0.24, green: 0.55, blue: 0.43) // 海苔绿
    static let warn = Color(red: 0.77, green: 0.48, blue: 0.29)

    static var sidebarFill: Color {
        Color(nsColor: .underPageBackgroundColor)
    }
}

struct GlassSidebarTab: View {
    let lens: PanelLens
    let selected: Bool
    let showDot: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: lens.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                Text(lens.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer(minLength: 0)
                if showDot {
                    Circle()
                        .fill(AppChrome.accent)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? AppChrome.accent.opacity(0.18) : (hovering ? Color.primary.opacity(0.06) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? AppChrome.accent.opacity(0.35) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct GlassPanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func glassPanel() -> some View {
        modifier(GlassPanelBackground())
    }
}
