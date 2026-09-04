import AppKit
import SwiftUI

/// One title-bar tab showing its live icon and actual pane composition.
struct HorizontalWorkspaceTab: View {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var isHovering = false
    @State
    private var isHoverCardPresented = false
    @State
    private var hoverPresentationTask: Task<Void, Never>?
    @State
    private var isCloseButtonHovering = false
    let tab: TerminalTab
    let index: Int
    let projectDirectory: String?
    let isActive: Bool
    let showsTabIndexHint: Bool
    var hoverSuppressed = false
    var hoverEnabled = true
    var fixedSize: CGSize?
    let onSelect: () -> Void
    let onClose: () -> Void

    private var panes: [Pane] { tab.splitRoot.allPanes() }
    private var tabIndexNumber: Int { index + 1 }
    private var trailingAccessoryPadding: CGFloat {
        max(28, CGFloat(String(tabIndexNumber).count * 6 + 15))
    }

    private var tabMaximumWidth: CGFloat {
        guard tab.customTitle == nil, panes.count > 1 else { return 220 }
        return min(CGFloat(panes.count) * 112 + 32, 380)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
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
                .padding(.leading, isActive ? 16 : 9)
                // Reserve the widest trailing accessory even while it is
                // hidden, so Command hints and hover never cover or shift the
                // title. The normal 28pt slot also fits two-digit indices.
                .padding(.trailing, trailingAccessoryPadding)
                .horizontalTabSize(
                    fixedSize: fixedSize,
                    minimumWidth: isActive ? 94 : 78,
                    maximumWidth: tabMaximumWidth
                )
                .background {
                    if !isActive, isHovering {
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.10))
                    }
                }
                .horizontalActiveTabMaterial(isActive: isActive)
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)

            if showsTabIndexHint {
                HorizontalTabIndexShortcutHint(number: tabIndexNumber, isActive: isActive)
                    .padding(.trailing, 5)
                    .transition(
                        reduceMotion
                            ? .identity
                            : .asymmetric(
                                insertion: .opacity.combined(
                                    with: .scale(scale: 0.92, anchor: .trailing)
                                ),
                                removal: .opacity
                            )
                    )
                    .allowsHitTesting(false)
            } else if isHovering {
                Button {
                    hoverPresentationTask?.cancel()
                    isHoverCardPresented = false
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .background {
                            if isCloseButtonHovering {
                                Circle()
                                    .fill(Color.primary.opacity(0.10))
                            }
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .contentShape(Circle())
                .padding(.trailing, 5)
                .help("Close Tab")
                .accessibilityLabel("Close Tab")
                .onHover { hovering in
                    isCloseButtonHovering = hovering
                    if hovering {
                        hoverPresentationTask?.cancel()
                        isHoverCardPresented = false
                    }
                }
                .transition(.identity)
            }
        }
        // Command is a high-frequency keyboard gesture: keep the requested
        // materialization nearly instant and avoid spring/bounce latency.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: showsTabIndexHint)
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
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, isHovering, !hoverSuppressed else { return }
            isHoverCardPresented = true
        }
    }
}

/// A compact keycap-like material that reveals a tab's Cmd+number shortcut.
private struct HorizontalTabIndexShortcutHint: View {
    let number: Int
    let isActive: Bool

    var body: some View {
        Text(number, format: .number.grouping(.never))
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isActive ? .primary : .secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18)
            .frame(height: 18)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        isActive
                            ? Color.primary.opacity(0.13)
                            : Color(nsColor: .windowBackgroundColor).opacity(0.72)
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(isActive ? 0.16 : 0.10), lineWidth: 0.5)
                    }
            }
            .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
            .accessibilityHidden(true)
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
