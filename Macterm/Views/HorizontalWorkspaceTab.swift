import AppKit
import SwiftUI

/// One title-bar tab showing its live icon and actual pane composition.
struct HorizontalWorkspaceTab: View {
    @State
    private var isHovering = false
    @State
    private var isHoverCardPresented = false
    @State
    private var hoverPresentationTask: Task<Void, Never>?
    let tab: TerminalTab
    let index: Int
    let projectDirectory: String?
    let isActive: Bool
    var hoverSuppressed = false
    var hoverEnabled = true
    var fixedSize: CGSize?
    let onSelect: () -> Void

    private var panes: [Pane] { tab.splitRoot.allPanes() }
    private var tabMaximumWidth: CGFloat {
        guard tab.customTitle == nil, panes.count > 1 else { return 220 }
        return min(CGFloat(panes.count) * 112 + 32, 380)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                HorizontalTabIcon(tab: tab, index: index + 1)

                if tab.customTitle == nil, panes.count > 1 {
                    HStack(spacing: 7) {
                        ForEach(Array(panes.enumerated()), id: \.element.id) { paneIndex, pane in
                            if paneIndex > 0 {
                                Divider()
                                    .frame(height: 14)
                            }
                            HorizontalPaneTitleSegment(
                                pane: pane,
                                projectDirectory: projectDirectory,
                                isActive: isActive
                            )
                        }
                    }
                } else {
                    Text(tab.sidebarRowTitle(projectDirectory: projectDirectory))
                        .font(.system(size: 12, weight: isActive ? .medium : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if panes.count > 1 {
                        HorizontalSplitLayoutGlyph(
                            splitRoot: tab.splitRoot,
                            focusedPaneID: tab.focusedPaneID
                        )
                    }
                }
            }
            .foregroundStyle(isActive ? .primary : .secondary)
            .padding(.horizontal, isActive ? 16 : 9)
            .horizontalTabSize(
                fixedSize: fixedSize,
                minimumWidth: isActive ? 94 : 78,
                maximumWidth: tabMaximumWidth
            )
            .background {
                if !isActive, isHovering {
                    Capsule(style: .continuous)
                        .fill(MactermTheme.hover)
                }
            }
            .horizontalActiveTabMaterial(isActive: isActive)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            updateHover(hovering)
        }
        .onChange(of: hoverSuppressed) { _, suppressed in
            if suppressed { updateHover(false) }
        }
        .background {
            ArrowlessPopoverPresenter(
                isPresented: $isHoverCardPresented,
                preferredWidth: 300,
                acceptsKeyboardInput: false,
                content: AnyView(
                    HorizontalTabHoverCard(tab: tab, projectDirectory: projectDirectory)
                )
            )
        }
        .onDisappear {
            hoverPresentationTask?.cancel()
        }
    }

    private func updateHover(_ hovering: Bool) {
        isHovering = hovering && hoverEnabled && !hoverSuppressed
        hoverPresentationTask?.cancel()
        guard isHovering else {
            isHoverCardPresented = false
            return
        }
        hoverPresentationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, isHovering, !hoverSuppressed else { return }
            isHoverCardPresented = true
        }
    }
}

private struct HorizontalPaneTitleSegment: View {
    let pane: Pane
    let projectDirectory: String?
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            if let agent = pane.agentIcon {
                HorizontalAgentIconMark(agent: agent, size: 10)
            }
            Text(pane.sidebarSegmentTitle(projectDirectory: projectDirectory))
                .font(.system(size: 12, weight: isActive ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(minWidth: 42, maxWidth: 104, alignment: .leading)
    }
}

/// Miniature of the actual split tree, preserving nested direction and ratio.
private struct HorizontalSplitLayoutGlyph: View {
    let splitRoot: SplitNode
    let focusedPaneID: UUID?

    private var paneFrames: [UUID: CGRect] {
        splitRoot.paneFrames()
    }

    var body: some View {
        Canvas { context, size in
            for (paneID, unitFrame) in paneFrames {
                let frame = CGRect(
                    x: unitFrame.minX * size.width,
                    y: unitFrame.minY * size.height,
                    width: unitFrame.width * size.width,
                    height: unitFrame.height * size.height
                ).insetBy(dx: 0.5, dy: 0.5)
                let path = Path(roundedRect: frame, cornerRadius: 1)
                if paneID == focusedPaneID {
                    context.fill(path, with: .color(MactermTheme.fgDim.opacity(0.28)))
                }
                context.stroke(path, with: .color(MactermTheme.fgDim), lineWidth: 0.75)
            }
        }
        .frame(width: 18, height: 12)
        .accessibilityLabel("Split panes")
    }
}
