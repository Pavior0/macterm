import SwiftUI

/// MRU chooser shown while the Recent Tab shortcut is held.
struct RecentTabSwitcherOverlay: View {
    @Environment(AppState.self)
    private var appState
    @Environment(ProjectStore.self)
    private var projectStore
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @State
    private var previewStore = RecentTabPreviewStore()

    private static let maximumPanelWidth: CGFloat = 1080
    private static let panelHorizontalMargin: CGFloat = 36

    var body: some View {
        GeometryReader { geometry in
            if let cycle = appState.recentTabCycle,
               cycle.showsSwitcher,
               let workspace = appState.workspaces[cycle.projectID]
            {
                let tabMetadataByID = Dictionary(uniqueKeysWithValues: workspace.tabs.enumerated().map { index, tab in
                    (tab.id, (tab: tab, sidebarIndex: index + 1))
                })
                let projectDirectory = projectStore.projects.first(where: { $0.id == cycle.projectID })?.path
                let items = cycle.tabIDs.compactMap { tabID -> RecentTabSwitcherItem? in
                    guard let metadata = tabMetadataByID[tabID] else { return nil }
                    return RecentTabSwitcherItem(
                        tab: metadata.tab,
                        sidebarIndex: metadata.sidebarIndex,
                        projectDirectory: projectDirectory
                    )
                }
                let panelWidth = min(
                    RecentTabSwitcherPanel.contentWidth(for: items.count),
                    max(geometry.size.width - (Self.panelHorizontalMargin * 2), 0),
                    Self.maximumPanelWidth
                )
                ZStack {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { appState.cancelRecentTabCycle() }
                        .accessibilityHidden(true)

                    RecentTabSwitcherPanel(
                        items: items,
                        selectedTabID: cycle.selectedTabID,
                        previewStore: previewStore
                    )
                    .frame(width: panelWidth)
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
    let projectDirectory: String?

    var id: UUID { tab.id }
}

private struct RecentTabSwitcherPanel: View {
    @Environment(AppState.self)
    private var appState

    let items: [RecentTabSwitcherItem]
    let selectedTabID: UUID
    let previewStore: RecentTabPreviewStore

    /// Suppresses keyboard-style auto-scrolling for the next highlight made
    /// by the pointer, so manual scrolling never moves the strip underneath it.
    @State
    private var selectionFromHover = false
    @State
    private var cardFrames: [UUID: ClosedRange<CGFloat>] = [:]

    fileprivate static let cardWidth: CGFloat = 202
    private static let cardHeight: CGFloat = 154
    private static let cardSpacing: CGFloat = 6
    private static let contentInset: CGFloat = 8
    private let cardSpace = "recentTabSwitcherCards"

    static func contentWidth(for itemCount: Int) -> CGFloat {
        let cards = CGFloat(itemCount) * cardWidth
        let spacing = CGFloat(max(itemCount - 1, 0)) * cardSpacing
        return cards + spacing + (contentInset * 2)
    }

    var body: some View {
        let tabs = items.map(\.tab)
        let paneIDs = tabs.flatMap { $0.splitRoot.allPanes().map(\.id) }

        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: Self.cardSpacing) {
                    ForEach(items) { item in
                        Button {
                            appState.commitRecentTabCycle(selecting: item.id)
                        } label: {
                            RecentTabSwitcherCard(
                                tab: item.tab,
                                sidebarIndex: item.sidebarIndex,
                                projectDirectory: item.projectDirectory,
                                isSelected: item.id == selectedTabID,
                                previewStore: previewStore
                            )
                            .frame(width: Self.cardWidth, height: Self.cardHeight)
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                        .background(
                            GeometryReader { geometry in
                                let frame = geometry.frame(in: .named(cardSpace))
                                Color.clear.preference(
                                    key: RecentTabSwitcherCardFramesKey.self,
                                    value: [item.id: frame.minX ... frame.maxX]
                                )
                            }
                        )
                    }
                }
                .padding(Self.contentInset)
            }
            .scrollIndicators(.visible)
            .coordinateSpace(name: cardSpace)
            .frame(height: Self.cardHeight + (Self.contentInset * 2))
            .onPreferenceChange(RecentTabSwitcherCardFramesKey.self) { cardFrames = $0 }
            .onContinuousHover(coordinateSpace: .named(cardSpace)) { phase in
                guard case let .active(point) = phase,
                      let tabID = cardFrames.first(where: { $0.value.contains(point.x) })?.key,
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
        .task(id: paneIDs) {
            await previewStore.refreshTabPreviews(tabs)
        }
    }
}

private struct RecentTabSwitcherCard: View {
    let tab: TerminalTab
    let sidebarIndex: Int
    let projectDirectory: String?
    let isSelected: Bool
    let previewStore: RecentTabPreviewStore

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
        VStack(alignment: .leading, spacing: 7) {
            RecentTabTerminalPreview(tab: tab, previewStore: previewStore)
                .frame(maxWidth: .infinity)
                .frame(height: 112)

            HStack(spacing: 7) {
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
                .frame(width: 18)

                Text(tab.horizontalTabTitle(projectDirectory: projectDirectory))
                    .font(.callout)
                    .foregroundStyle(MactermTheme.fg)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(sidebarIndex)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(MactermTheme.fgMuted.opacity(0.65))
                    .fixedSize()
            }
        }
        .padding(7)
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

private struct RecentTabTerminalPreview: View {
    let tab: TerminalTab
    let previewStore: RecentTabPreviewStore

    var body: some View {
        GeometryReader { geometry in
            let frames = tab.splitRoot.paneFrames(
                in: CGRect(origin: .zero, size: geometry.size)
            )

            ZStack(alignment: .topLeading) {
                MactermTheme.bg

                ForEach(tab.splitRoot.allPanes()) { pane in
                    if let frame = frames[pane.id] {
                        panePreview(pane)
                            .frame(width: frame.width, height: frame.height)
                            .clipped()
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(MactermTheme.border.opacity(0.7), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.24), radius: 5, x: 0, y: 2)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func panePreview(_ pane: Pane) -> some View {
        if let image = previewStore.previewImage(for: pane.id) {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MactermTheme.bg)
        } else {
            RecentTabTerminalPlaceholder()
        }
    }
}

private struct RecentTabTerminalPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            placeholderLine(width: 0.62, showsPrompt: true)
            placeholderLine(width: 0.78, showsPrompt: false)
            placeholderLine(width: 0.42, showsPrompt: true)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(MactermTheme.bg)
    }

    private func placeholderLine(width: CGFloat, showsPrompt: Bool) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 6) {
                if showsPrompt {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .semibold))
                        .frame(width: 8)
                }

                Capsule()
                    .frame(width: max(geometry.size.width * width - (showsPrompt ? 14 : 0), 12), height: 4)
            }
            .foregroundStyle(MactermTheme.fgMuted.opacity(0.26))
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 8)
    }
}

private struct RecentTabSwitcherCardFramesKey: PreferenceKey {
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
