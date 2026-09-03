import AppKit
import SwiftUI

// Overflow-aware tab strip that keeps the selected workspace tab visible.

struct HorizontalWorkspaceTabs: View {
    private static let coordinateSpace = "horizontal-workspace-tab-strip"

    @Environment(AppState.self)
    private var appState
    @Environment(ProjectStore.self)
    private var projectStore
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var draggedTabID: UUID?
    @State
    private var tabFrames: [UUID: CGRect] = [:]
    @State
    private var dragLocation: CGPoint?
    @State
    private var dragGrabOffsetX: CGFloat = 0
    @State
    private var dragOriginY: CGFloat = 0
    @State
    private var dragSourceSize: CGSize?
    @State
    private var isContextMenuTracking = false
    @State
    private var renameTabID: UUID?
    @State
    private var renameText = ""
    let workspace: Workspace
    let project: Project?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(Array(workspace.tabs.enumerated()), id: \.element.id) { index, tab in
                        HorizontalWorkspaceTab(
                            tab: tab,
                            index: index,
                            projectDirectory: project?.id == PinnedTabs.projectID ? nil : project?.path,
                            isActive: tab.id == workspace.activeTabID,
                            hoverSuppressed: draggedTabID != nil || isContextMenuTracking,
                            onSelect: {
                                appState.selectTab(tab.id, projectID: workspace.projectID)
                            }
                        )
                        .id(tab.id)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: HorizontalTabFramePreferenceKey.self,
                                    value: [
                                        tab.id: geometry.frame(
                                            in: .named(Self.coordinateSpace)
                                        ),
                                    ]
                                )
                            }
                        }
                        // The real row keeps its slot in layout but disappears
                        // under the pointer-following preview drawn above the strip.
                        .opacity(draggedTabID == tab.id ? 0 : 1)
                        .highPriorityGesture(
                            DragGesture(
                                minimumDistance: 4,
                                coordinateSpace: .named(Self.coordinateSpace)
                            )
                            .onChanged { value in
                                updateTabDrag(
                                    tabID: tab.id,
                                    startLocation: value.startLocation,
                                    location: value.location
                                )
                            }
                            .onEnded { _ in
                                withAnimation(reduceMotion ? nil : .smooth(duration: 0.12)) {
                                    draggedTabID = nil
                                    dragLocation = nil
                                    dragSourceSize = nil
                                }
                            }
                        )
                        .contextMenu {
                            tabContextMenu(tab: tab, index: index)
                        }
                        .overlay(alignment: .trailing) {
                            if showsSeparator(after: index) {
                                Rectangle()
                                    .fill(MactermTheme.fgDim.opacity(0.28))
                                    .frame(width: 1, height: 12)
                                    .offset(x: 2)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
                .padding(.horizontal, 1)
                .animation(reduceMotion ? nil : .smooth(duration: 0.16), value: workspace.tabs.map(\.id))
            }
            .coordinateSpace(name: Self.coordinateSpace)
            .onPreferenceChange(HorizontalTabFramePreferenceKey.self) { frames in
                tabFrames = frames
            }
            .overlay(alignment: .topLeading) {
                draggedTabPreview
            }
            .onAppear {
                Task { @MainActor in
                    await Task.yield()
                    scrollToActiveTab(proxy, animated: false)
                }
            }
            .onChange(of: workspace.activeTabID) {
                scrollToActiveTab(proxy, animated: true)
            }
            .onChange(of: workspace.tabs.count) {
                scrollToActiveTab(proxy, animated: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
                isContextMenuTracking = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                isContextMenuTracking = false
            }
        }
        .frame(maxWidth: .infinity)
        .alert("Rename Tab", isPresented: renameIsPresented) {
            TextField("Tab name", text: $renameText)
            Button("Cancel", role: .cancel) {
                renameTabID = nil
            }
            Button("Save") {
                commitTabRename()
            }
        }
    }

    private var renameIsPresented: Binding<Bool> {
        Binding(
            get: { renameTabID != nil },
            set: { presented in
                if !presented { renameTabID = nil }
            }
        )
    }

    @ViewBuilder
    private func tabContextMenu(tab: TerminalTab, index: Int) -> some View {
        Button("Rename Tab") {
            renameText = tab.customTitle ?? ""
            renameTabID = tab.id
        }
        if tab.splitRoot.allPanes().count > 1 {
            Button("Separate Panes") {
                appState.separateTabPanes(tab.id, projectID: workspace.projectID)
            }
        }

        Divider()

        Button("Move Left") {
            appState.reorderTab(tab.id, inProject: workspace.projectID, toIndex: index - 1)
        }
        .disabled(index <= 0)
        Button("Move Right") {
            appState.reorderTab(tab.id, inProject: workspace.projectID, toIndex: index + 2)
        }
        .disabled(index >= workspace.tabs.count - 1)

        if workspace.projectID == PinnedTabs.projectID {
            if !projectStore.projects.isEmpty {
                Menu("Unpin to Project") {
                    ForEach(projectStore.projects) { destination in
                        Button(destination.name) {
                            appState.moveTab(
                                tab.id,
                                from: PinnedTabs.projectID,
                                to: destination.id,
                                destPath: destination.path
                            )
                        }
                    }
                }
            }
            Divider()
            Button("Unpin Tab") {
                appState.unpinTab(tab.id, projects: projectStore.projects)
            }
        } else {
            let moveTargets = projectStore.projects.filter { $0.id != workspace.projectID }
            if !moveTargets.isEmpty {
                Menu("Move to Project") {
                    ForEach(moveTargets) { destination in
                        Button(destination.name) {
                            appState.moveTab(
                                tab.id,
                                from: workspace.projectID,
                                to: destination.id,
                                destPath: destination.path
                            )
                        }
                    }
                }
            }
            Button("Pin Tab") {
                appState.pinTab(tab.id, fromProject: workspace.projectID)
            }
        }

        Divider()
        Group {
            Button("Close Tab", role: .destructive) {
                appState.requestCloseTab(tab.id, projectID: workspace.projectID)
            }
            Button("Close Other Tabs", role: .destructive) {
                requestCloseTabs(workspace.tabs.filter { $0.id != tab.id })
            }
            .disabled(workspace.tabs.count <= 1)
            Button("Close Tabs to the Right", role: .destructive) {
                requestCloseTabs(Array(workspace.tabs.dropFirst(index + 1)))
            }
            .disabled(index >= workspace.tabs.count - 1)
        }
    }

    private func requestCloseTabs(_ tabs: [TerminalTab]) {
        let references = tabs.map { (tabID: $0.id, projectID: workspace.projectID) }
        guard !references.isEmpty else { return }
        appState.requestRemoveSelection(projectIDs: [], tabs: references) {
            appState.closeTabs(references)
        }
    }

    private func commitTabRename() {
        defer { renameTabID = nil }
        guard let renameTabID,
              let tab = workspace.tabs.first(where: { $0.id == renameTabID })
        else { return }
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        tab.customTitle = title.isEmpty ? nil : title
        appState.saveWorkspaces()
    }

    @ViewBuilder
    private var draggedTabPreview: some View {
        if let draggedTabID,
           let dragLocation,
           let draggedTab = workspace.tabs.first(where: { $0.id == draggedTabID }),
           let index = workspace.tabs.firstIndex(where: { $0.id == draggedTabID })
        {
            HorizontalWorkspaceTab(
                tab: draggedTab,
                index: index,
                projectDirectory: project?.id == PinnedTabs.projectID ? nil : project?.path,
                isActive: draggedTab.id == workspace.activeTabID,
                hoverSuppressed: true,
                hoverEnabled: false,
                fixedSize: dragSourceSize,
                onSelect: {}
            )
            .allowsHitTesting(false)
            .offset(
                x: dragLocation.x - dragGrabOffsetX,
                y: dragOriginY
            )
            .zIndex(1)
        }
    }

    private func updateTabDrag(tabID: UUID, startLocation: CGPoint, location: CGPoint) {
        if draggedTabID == nil {
            guard let frame = tabFrames[tabID] else { return }
            draggedTabID = tabID
            dragGrabOffsetX = startLocation.x - frame.minX
            dragOriginY = frame.minY
            dragSourceSize = frame.size
        }
        guard draggedTabID == tabID else { return }
        dragLocation = location

        let orderedTabIDs = workspace.tabs.map(\.id)
        let visibleFrames = tabFrames.sorted { $0.value.midX < $1.value.midX }
        guard let sourceIndex = orderedTabIDs.firstIndex(of: tabID),
              let visibleDestinationIndex = visibleFrames.indices.min(by: {
                  abs(visibleFrames[$0].value.midX - location.x)
                      < abs(visibleFrames[$1].value.midX - location.x)
              }),
              let firstVisibleModelIndex = visibleFrames
              .compactMap({ orderedTabIDs.firstIndex(of: $0.key) })
              .min()
        else { return }

        let destinationIndex = min(
            firstVisibleModelIndex + visibleDestinationIndex,
            orderedTabIDs.count - 1
        )
        guard sourceIndex != destinationIndex else { return }

        // Workspace.moveTab receives a pre-removal insertion offset. Crossing
        // toward the trailing edge therefore includes the dragged tab's slot.
        let dropOffset = destinationIndex > sourceIndex
            ? destinationIndex + 1
            : destinationIndex
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.16)) {
            appState.reorderTab(
                tabID,
                inProject: workspace.projectID,
                toIndex: dropOffset
            )
        }
    }

    /// The selected capsule provides its own boundary, so separators only sit
    /// between two inactive tabs rather than doubling either selected edge.
    private func showsSeparator(after index: Int) -> Bool {
        guard index >= 0, index + 1 < workspace.tabs.count else { return false }
        let activeTabID = workspace.activeTabID
        return workspace.tabs[index].id != activeTabID
            && workspace.tabs[index + 1].id != activeTabID
    }

    private func scrollToActiveTab(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let activeTabID = workspace.activeTabID else { return }
        if animated, !reduceMotion {
            withAnimation(.easeOut(duration: 0.16)) {
                proxy.scrollTo(activeTabID, anchor: .trailing)
            }
        } else {
            proxy.scrollTo(activeTabID, anchor: .trailing)
        }
    }
}

private struct HorizontalTabFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
