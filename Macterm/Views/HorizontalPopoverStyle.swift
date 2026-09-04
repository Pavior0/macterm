import AppKit
import SwiftUI

/// Applies one neutral material to an anchored horizontal-navigation panel.
extension View {
    @ViewBuilder
    func horizontalPopoverSurface(cornerRadius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        background {
            shape
                .fill(.thinMaterial)
                .overlay {
                    // Prevent the transparent panel from inheriting a cool tint.
                    shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
                }
        }
        .clipShape(shape)
    }

    /// Shows hover and selection without nesting another material layer.
    func horizontalNavigationStateSurface(
        isHovering: Bool,
        isSelected: Bool = false,
        cornerRadius: CGFloat = 8
    ) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(horizontalNavigationStateColor(
                    isHovering: isHovering,
                    isSelected: isSelected
                ))
        }
    }

    private func horizontalNavigationStateColor(isHovering: Bool, isSelected: Bool) -> Color {
        if isSelected {
            return Color.primary.opacity(isHovering ? 0.11 : 0.07)
        }
        return isHovering ? Color.primary.opacity(0.08) : .clear
    }
}
