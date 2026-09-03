import SwiftUI

/// The shared floating surface for horizontal-tab navigation panels.
/// Text-dense panels use regular glass for legibility; clear glass is reserved
/// for compact controls that can tolerate more background interference.
extension View {
    @ViewBuilder
    func horizontalPopoverSurface(cornerRadius: CGFloat = 12, showsGlassEdge: Bool = true) -> some View {
        if #available(macOS 26.0, *) {
            if showsGlassEdge {
                glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            } else {
                background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
                    .clipShape(.rect(cornerRadius: cornerRadius))
            }
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
                }
        }
    }
}
