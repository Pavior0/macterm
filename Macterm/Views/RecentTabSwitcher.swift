import SwiftUI

/// MRU chooser shown while the Recent Tab shortcut is held.
struct RecentTabSwitcherOverlay: View {
    @Environment(AppState.self)
    private var appState
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    private static let panelWidth: CGFloat = 460
    static let rowHeight: CGFloat = 54
    static let maximumVisibleRows = 6

    var body: some View {
        GeometryReader { geometry in
            if let cycle = appState.recentTabCycle,
               cycle.showsSwitcher,
               let workspace = appState.workspaces[cycle.projectID]
            {
                let tabMetadataByID = Dictionary(uniqueKeysWithValues: workspace.tabs.enumerated().map { index, tab in
                    (tab.id, (tab: tab, sidebarIndex: index + 1))
                })
                let items = cycle.tabIDs.compactMap { tabID -> RecentTabSwitcherItem? in
                    guard let metadata = tabMetadataByID[tabID] else { return nil }
                    return RecentTabSwitcherItem(
                        tab: metadata.tab,
                        sidebarIndex: metadata.sidebarIndex
                    )
                }
                ZStack {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { appState.cancelRecentTabCycle() }
                        .accessibilityHidden(true)

                    RecentTabSwitcherPanel(
                        items: items,
                        selectedTabID: cycle.selectedTabID
                    )
                    .frame(width: Self.panelWidth)
                    .recentTabSwitcherBackground(reduceTransparency: reduceTransparency)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(MactermTheme.border.opacity(reduceTransparency ? 1 : 0.8), lineWidth: 1)
                    }
                    .shadow(color: MactermTheme.border, radius: 24, x: 0, y: 10)
                    .offset(y: -geometry.size.height * 0.05)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Recent tabs")
                }
            }
        }
    }
}

private struct RecentTabSwitcherItem: Identifiable {
    let tab: TerminalTab
    let sidebarIndex: Int

    var id: UUID { tab.id }
}

private struct RecentTabSwitcherPanel: View {
    @Environment(AppState.self)
    private var appState

    let items: [RecentTabSwitcherItem]
    let selectedTabID: UUID

    /// Suppresses keyboard-style auto-scrolling for the next highlight made
    /// by the pointer, so manual scrolling never moves the list underneath it.
    @State
    private var selectionFromHover = false
    @State
    private var rowFrames: [UUID: ClosedRange<CGFloat>] = [:]

    private static let rowSpacing: CGFloat = 2
    private static let contentInset: CGFloat = 6
    private let rowSpace = "recentTabSwitcherRows"

    private var visibleRowCount: Int {
        min(items.count, RecentTabSwitcherOverlay.maximumVisibleRows)
    }

    private var listHeight: CGFloat {
        let rows = CGFloat(visibleRowCount) * RecentTabSwitcherOverlay.rowHeight
        let spacing = CGFloat(max(visibleRowCount - 1, 0)) * Self.rowSpacing
        return rows + spacing + (Self.contentInset * 2)
    }

    private var showsScrollIndicator: Bool {
        items.count > RecentTabSwitcherOverlay.maximumVisibleRows
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: Self.rowSpacing) {
                    ForEach(items) { item in
                        Button {
                            appState.commitRecentTabCycle(selecting: item.id)
                        } label: {
                            RecentTabSwitcherRow(
                                tab: item.tab,
                                sidebarIndex: item.sidebarIndex,
                                isSelected: item.id == selectedTabID
                            )
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                        .background(
                            GeometryReader { geometry in
                                let frame = geometry.frame(in: .named(rowSpace))
                                Color.clear.preference(
                                    key: RecentTabSwitcherRowFramesKey.self,
                                    value: [item.id: frame.minY ... frame.maxY]
                                )
                            }
                        )
                    }
                }
                .padding(Self.contentInset)
            }
            .scrollIndicators(showsScrollIndicator ? .visible : .hidden)
            .coordinateSpace(name: rowSpace)
            .frame(height: listHeight)
            .onPreferenceChange(RecentTabSwitcherRowFramesKey.self) { rowFrames = $0 }
            .onContinuousHover(coordinateSpace: .named(rowSpace)) { phase in
                guard case let .active(point) = phase,
                      let tabID = rowFrames.first(where: { $0.value.contains(point.y) })?.key,
                      selectedTabID != tabID
                else { return }
                selectionFromHover = true
                appState.highlightRecentTab(tabID)
            }
            .onAppear { proxy.scrollTo(selectedTabID, anchor: .center) }
            .onChange(of: selectedTabID) { _, id in
                if selectionFromHover {
                    selectionFromHover = false
                } else {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .foregroundStyle(MactermTheme.fg)
    }
}

private struct RecentTabSwitcherRow: View {
    let tab: TerminalTab
    let sidebarIndex: Int
    let isSelected: Bool

    @AppStorage(Preferences.Keys.tabIconSymbol, store: Preferences.defaults)
    private var tabIconSymbol = "terminal"
    @AppStorage(Preferences.Keys.showAgentIcons, store: Preferences.defaults)
    private var showAgentIcons = true
    @AppStorage(Preferences.Keys.showTabStatusIndicator, store: Preferences.defaults)
    private var showTabStatusIndicator = false
    @AppStorage(Preferences.Keys.showSpinnerOverAgentIcons, store: Preferences.defaults)
    private var showSpinnerOverAgentIcons = true

    private var agentIcon: AgentIcon? { showAgentIcons ? tab.agentIcon : nil }
    private var iconSymbol: String {
        tabIconSymbol == Preferences.noIcon ? "terminal" : tabIconSymbol
    }

    private var paneCount: Int { tab.splitRoot.allPanes().count }

    var body: some View {
        HStack(spacing: 11) {
            Group {
                if showTabStatusIndicator {
                    TabStatusIcon(
                        state: tab.executionState,
                        symbol: iconSymbol,
                        index: sidebarIndex,
                        agent: agentIcon,
                        spinnerOverAgent: showSpinnerOverAgentIcons
                    )
                } else {
                    WorkspaceItemIcon(symbol: iconSymbol, index: sidebarIndex, agent: agentIcon)
                        .foregroundStyle(MactermTheme.fgMuted)
                }
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(tab.sidebarTitle)
                    .font(.body)
                    .foregroundStyle(MactermTheme.fg)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 7) {
                    if let status = statusText {
                        Text(status)
                            .foregroundStyle(statusColor)
                    }
                    if let path = workingDirectoryText {
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if paneCount > 1 {
                        Text("\(paneCount) panes")
                            .fixedSize()
                    }
                }
                .font(.caption)
                .foregroundStyle(MactermTheme.fgMuted)
            }

            Text("\(sidebarIndex)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(MactermTheme.fgMuted.opacity(0.65))
                .frame(minWidth: 18, alignment: .trailing)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: RecentTabSwitcherOverlay.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? MactermTheme.surface : .clear)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var statusText: String? {
        switch tab.executionState {
        case .idle: nil
        case .running: "Running"
        case .done: "Completed"
        }
    }

    private var statusColor: Color {
        switch tab.executionState {
        case .idle: MactermTheme.fgMuted
        case .running: MactermTheme.fg
        case .done: MactermTheme.success
        }
    }

    private var workingDirectoryText: String? {
        guard let pane = tab.focusedPane else { return nil }
        let path = pane.isRemote
            ? pane.projectPath
            : (pane.nsView?.currentPwd ?? pane.projectPath)
        guard !path.isEmpty else { return nil }
        return pane.isRemote ? path : (path as NSString).abbreviatingWithTildeInPath
    }

    private var accessibilityLabel: String {
        [
            "Tab \(sidebarIndex)",
            tab.sidebarTitle,
            statusText,
            workingDirectoryText,
            paneCount > 1 ? "\(paneCount) panes" : nil,
        ]
        .compactMap(\.self)
        .joined(separator: ", ")
    }
}

private struct RecentTabSwitcherRowFramesKey: PreferenceKey {
    static let defaultValue: [UUID: ClosedRange<CGFloat>] = [:]

    static func reduce(
        value: inout [UUID: ClosedRange<CGFloat>],
        nextValue: () -> [UUID: ClosedRange<CGFloat>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    /// Uses Liquid Glass on macOS 26 and native material on older systems.
    @ViewBuilder
    func recentTabSwitcherBackground(reduceTransparency: Bool) -> some View {
        if reduceTransparency {
            background(MactermTheme.bg, in: .rect(cornerRadius: 18))
        } else if #available(macOS 26.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: 18))
        } else {
            background(.regularMaterial, in: .rect(cornerRadius: 18))
        }
    }
}
