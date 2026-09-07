import SwiftUI

/// The floating-panel chrome shared by every transient overlay the app puts
/// over the terminal (command palette, tab switcher): liquid glass on
/// macOS 26, the closest native material below it, plus the hairline border
/// and drop shadow that make it read as a native floating surface rather
/// than a view drawn inside the window.
///
/// One modifier rather than a copy per overlay, so a new overlay can't drift
/// from the palette's look — the palette's radius (16) matches the macOS
/// Tahoe window corner radius, and anything floating beside it must too.
/// One floating panel's drop shadow, as a unit rather than loose parameters
/// so a caller can't mix a radius from one look with a color from another.
struct GlassPanelShadow {
    let color: Color
    let radius: CGFloat
    let y: CGFloat

    /// The palette's shadow — neutral black. The default every panel shares.
    static let standard = GlassPanelShadow(color: .black.opacity(0.35), radius: 20, y: 8)

    /// The tab switcher's — theme-colored, tracking the terminal palette, and
    /// a step wider and deeper (backported from our implementation): a strip
    /// of terminal previews reads better floating a little higher over the
    /// window than the palette does. MainActor because the theme color is.
    @MainActor
    static let theme = GlassPanelShadow(color: MactermTheme.border, radius: 24, y: 10)
}

extension View {
    func glassPanel(
        cornerRadius: CGFloat = GlassPanelMetrics.cornerRadius,
        shadow: GlassPanelShadow = .standard
    ) -> some View {
        glassPanelBackground(cornerRadius: cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(MactermTheme.border, lineWidth: 1)
            )
            .shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
    }

    /// Liquid glass on macOS 26; the closest native material on older systems.
    @ViewBuilder
    func glassPanelBackground(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}

enum GlassPanelMetrics {
    /// Matches the macOS Tahoe window corner radius.
    static let cornerRadius: CGFloat = 16
}
