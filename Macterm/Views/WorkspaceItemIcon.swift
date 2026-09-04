import SwiftUI

/// A tab icon with its execution status. Shared by the sidebar and Recent Tab
/// switcher so both surfaces use the same icon and sizing preferences.
struct TabStatusIcon: View {
    let state: TerminalExecutionState
    let symbol: String
    let index: Int
    var agent: AgentIcon?
    var spinnerOverAgent = true
    @AppStorage(Preferences.Keys.sidebarIconSize, store: Preferences.defaults)
    private var iconSizeRaw = SidebarIconSize.medium.rawValue

    private var size: SidebarIconSize {
        SidebarIconSize(rawValue: iconSizeRaw) ?? .medium
    }

    private var spinnerControlSize: ControlSize {
        size == .small ? .mini : .small
    }

    var body: some View {
        switch state {
        case .running:
            if let agent, !spinnerOverAgent {
                WorkspaceItemIcon(symbol: symbol, index: index, agent: agent)
                    .foregroundStyle(.secondary)
                    .help("Running")
            } else {
                let side = 16 * size.glyphScale
                ProgressView()
                    .controlSize(spinnerControlSize)
                    .tint(.secondary)
                    .help("Running")
                    .frame(width: side, height: side)
            }
        case .done:
            WorkspaceItemIcon(symbol: symbol, index: index, agent: agent)
                .foregroundStyle(.secondary)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(.background)
                        .frame(width: 7 * size.glyphScale, height: 7 * size.glyphScale)
                        .overlay(
                            Circle()
                                .fill(MactermTheme.success)
                                .frame(width: 5 * size.glyphScale, height: 5 * size.glyphScale)
                        )
                        .offset(x: 2.5 * size.glyphScale, y: 2.5 * size.glyphScale)
                }
                .help("Done")
        case .idle:
            WorkspaceItemIcon(symbol: symbol, index: index, agent: agent)
                .foregroundStyle(.secondary)
                .help("Idle")
        }
    }
}

struct WorkspaceItemIcon: View {
    let symbol: String
    let index: Int
    var agent: AgentIcon?
    @AppStorage(Preferences.Keys.sidebarIconSize, store: Preferences.defaults)
    private var iconSizeRaw = SidebarIconSize.medium.rawValue
    @ScaledMetric(relativeTo: .body)
    private var agentIconSize: CGFloat = 15

    private var size: SidebarIconSize {
        SidebarIconSize(rawValue: iconSizeRaw) ?? .medium
    }

    var body: some View {
        if let agent {
            let side = agentIconSize * size.glyphScale
            Image(agent.rawValue)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
                .foregroundStyle(agent.brandColor)
        } else if Preferences.numberIconChoices.contains(symbol) {
            NumberedItemIcon(index: index, variant: symbol, size: size)
        } else {
            Image(systemName: symbol)
                .imageScale(size.imageScale)
        }
    }
}

private extension SidebarIconSize {
    var imageScale: Image.Scale {
        switch self {
        case .small: .small
        case .medium: .medium
        case .large: .large
        }
    }
}

private struct NumberedItemIcon: View {
    let index: Int
    let variant: String
    var size: SidebarIconSize = .medium
    @ScaledMetric(relativeTo: .body)
    private var bodyFontSize: CGFloat = 13

    private var digitFont: Font {
        .system(size: bodyFontSize * size.glyphScale).monospacedDigit()
    }

    var body: some View {
        if variant == Preferences.numberIconPlain {
            Text("\(index)")
                .font(digitFont)
        } else if let suffix = shapeSuffix, (1 ... 50).contains(index) {
            Image(systemName: "\(index).\(suffix)")
                .imageScale(size.imageScale)
        } else {
            Text("\(index)")
                .font(digitFont)
        }
    }

    private var shapeSuffix: String? {
        switch variant {
        case Preferences.numberIconCircleFill: "circle.fill"
        case Preferences.numberIconCircle: "circle"
        case Preferences.numberIconSquareFill: "square.fill"
        case Preferences.numberIconSquare: "square"
        default: nil
        }
    }
}
