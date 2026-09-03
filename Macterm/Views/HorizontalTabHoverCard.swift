import AppKit
import SwiftUI

/// Delayed hover preview with information that the compact tab row cannot fit.
struct HorizontalTabHoverCard: View {
    private static let metadataOpacity = 0.72
    private static let quietMetadataOpacity = 0.58

    let tab: TerminalTab
    let projectDirectory: String?
    @State
    private var branchState = HorizontalTabBranchState.loading

    private var panes: [Pane] { tab.splitRoot.allPanes() }
    private var workingDirectory: String? {
        guard let pane = tab.focusedPane ?? panes.first, !pane.isRemote else { return nil }
        return pane.reportedWorkingDirectory ?? pane.projectPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                if let agent = tab.agentIcon {
                    HorizontalAgentIconMark(agent: agent, size: 16)
                } else {
                    Image(systemName: "terminal")
                        .foregroundStyle(.primary.opacity(Self.metadataOpacity))
                }

                Text(tab.sidebarTitle)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 8)
                statusLabel
            }

            if let workingDirectory {
                metadataRow(
                    icon: "folder",
                    text: ProjectPath.homeContracted(workingDirectory)
                )
            }
            if workingDirectory != nil {
                branchMetadataRow
            }
            if let agent = tab.agentIcon {
                metadataRow(icon: "sparkles", text: agent.displayName)
            }

            if panes.count > 1 {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(panes.prefix(4).enumerated()), id: \.element.id) { index, pane in
                        HStack(spacing: 7) {
                            Text("\(index + 1)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.primary.opacity(Self.quietMetadataOpacity))
                                .frame(width: 12, alignment: .trailing)
                            if let agent = pane.agentIcon {
                                HorizontalAgentIconMark(agent: agent, size: 11)
                            }
                            Text(pane.sidebarSegmentTitle(projectDirectory: projectDirectory))
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            if pane.id == tab.focusedPaneID {
                                Text("Focused")
                                    .font(.caption2)
                                    .foregroundStyle(.primary.opacity(Self.quietMetadataOpacity))
                            }
                        }
                        .font(.caption)
                    }
                    if panes.count > 4 {
                        Text("+\(panes.count - 4) more panes")
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(Self.metadataOpacity))
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 300)
        .horizontalPopoverSurface()
        .task(id: workingDirectory) {
            guard let workingDirectory else {
                branchState = .unavailable
                return
            }
            branchState = .loading
            let branch = await HorizontalTabGitBranchLookup.branch(at: workingDirectory)
            guard !Task.isCancelled else { return }
            if let branch {
                branchState = .available(branch)
            } else {
                branchState = .unavailable
            }
        }
    }

    @ViewBuilder
    private var branchMetadataRow: some View {
        switch branchState {
        case .loading:
            metadataRow(icon: "arrow.triangle.branch", text: "Checking branch…")
                .foregroundStyle(.primary.opacity(Self.quietMetadataOpacity))
        case let .available(branch):
            metadataRow(icon: "arrow.triangle.branch", text: branch)
        case .unavailable:
            metadataRow(icon: "arrow.triangle.branch", text: "No Git branch")
                .foregroundStyle(.primary.opacity(Self.quietMetadataOpacity))
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch tab.executionState {
        case .idle:
            Text("Idle")
                .foregroundStyle(.primary.opacity(Self.quietMetadataOpacity))
        case .running:
            Label("Running", systemImage: "circle.fill")
                .foregroundStyle(MactermTheme.warning)
        case .done:
            Label("Done", systemImage: "circle.fill")
                .foregroundStyle(MactermTheme.success)
        }
    }

    private func metadataRow(icon: String, text: String) -> some View {
        Label {
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: icon)
                .frame(width: 14)
        }
        .font(.caption)
        // Primary is the system's vibrant text color and adapts to the
        // window's appearance; a moderate opacity preserves hierarchy while
        // keeping metadata readable over Liquid Glass's changing backdrop.
        .foregroundStyle(.primary.opacity(Self.metadataOpacity))
    }
}

private enum HorizontalTabBranchState {
    case loading
    case available(String)
    case unavailable
}
