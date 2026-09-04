import SwiftUI

extension View {
    @ViewBuilder
    func horizontalNewTabMaterial(isHovering: Bool) -> some View {
        if #available(macOS 26.0, *) {
            if isHovering {
                glassEffect(.clear, in: .circle)
            } else {
                self
            }
        } else {
            background {
                if isHovering {
                    Circle().fill(MactermTheme.hover)
                }
            }
        }
    }

    /// A dragged preview lives in a full-width overlay, whose layout proposal
    /// would otherwise stretch the tab to its maximum width. Preserve the
    /// measured source geometry so both the capsule and its glass sampling
    /// region remain identical while dragging.
    @ViewBuilder
    func horizontalTabSize(
        fixedSize: CGSize?,
        minimumWidth: CGFloat,
        maximumWidth: CGFloat
    ) -> some View {
        if let fixedSize {
            frame(width: fixedSize.width, height: fixedSize.height)
        } else {
            frame(minWidth: minimumWidth, maxWidth: maximumWidth, minHeight: 26)
        }
    }

    /// Keep the active tab on native Liquid Glass while clipping the effect to
    /// its capsule. macOS 27 lets title-bar accessories draw outside their
    /// bounds; the explicit clip prevents glass depth from becoming a halo.
    @ViewBuilder
    func horizontalActiveTabMaterial(isActive: Bool) -> some View {
        if isActive {
            if #available(macOS 26.0, *) {
                glassEffect(.regular, in: .capsule)
                    .clipShape(Capsule(style: .continuous))
            } else {
                background(.regularMaterial, in: Capsule(style: .continuous))
            }
        } else {
            self
        }
    }
}
