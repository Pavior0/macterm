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

    /// A dragged preview lives in a full-width overlay, so preserve its source
    /// geometry instead of letting the overlay's layout proposal resize it.
    @ViewBuilder
    func horizontalTabSize(
        fixedSize: CGSize?,
        width: CGFloat
    ) -> some View {
        if let fixedSize {
            frame(
                width: fixedSize.width,
                height: fixedSize.height,
                alignment: .leading
            )
        } else {
            frame(width: width, alignment: .leading)
                .frame(minHeight: 26)
        }
    }

    /// Keep the active tab on native Liquid Glass while clipping the effect to
    /// its rounded shape. macOS 27 lets title-bar accessories draw outside
    /// their bounds; the explicit clip prevents glass depth from becoming a
    /// halo.
    @ViewBuilder
    func horizontalActiveTabMaterial(isActive: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        if isActive {
            if #available(macOS 26.0, *) {
                glassEffect(.regular, in: .rect(cornerRadius: 7))
                    .clipShape(shape)
            } else {
                background(.regularMaterial, in: shape)
            }
        } else {
            self
        }
    }
}
