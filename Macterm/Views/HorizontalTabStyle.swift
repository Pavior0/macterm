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

    /// Active tabs are a native Liquid Glass control layer on Tahoe. Older
    /// systems keep the same capsule geometry with the nearest system material.
    @ViewBuilder
    func horizontalActiveTabMaterial(isActive: Bool) -> some View {
        if isActive {
            if #available(macOS 26.0, *) {
                // Tab labels carry text, so use regular glass rather than the
                // highly translucent clear variant. Regular glass adapts the
                // backdrop's luminosity to preserve legibility.
                glassEffect(.regular, in: .capsule)
            } else {
                background(.regularMaterial, in: Capsule(style: .continuous))
                overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
                }
            }
        } else {
            self
        }
    }
}
