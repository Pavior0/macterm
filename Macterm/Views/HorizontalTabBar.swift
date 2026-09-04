import AppKit
import SwiftUI

/// Superlogical-style title-bar navigation for one project's horizontally scrolling tabs.
struct HorizontalTabBar: View {
    @Environment(AppState.self)
    private var appState
    @Environment(ProjectStore.self)
    private var projectStore
    @State
    private var isProjectSwitcherPresented = false
    @State
    private var isProjectSwitcherHovering = false
    @State
    private var isNewTabHovering = false

    private var activeProject: Project? {
        guard let projectID = appState.activeProjectID else { return nil }
        if projectID == PinnedTabs.projectID { return PinnedTabs.project }
        return projectStore.projects.first { $0.id == projectID }
    }

    private var activeWorkspace: Workspace? {
        guard let projectID = appState.activeProjectID else { return nil }
        return appState.workspaces[projectID]
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isProjectSwitcherPresented.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: activeProject?.isRemote == true ? "network" : "folder")
                        .foregroundStyle(.secondary)
                    Text(activeProject?.name ?? "Projects")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .horizontalNavigationStateSurface(
                    isHovering: isProjectSwitcherHovering,
                    isSelected: isProjectSwitcherPresented,
                    cornerRadius: 7
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isProjectSwitcherHovering = $0 }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(2)
            .help("Switch project")
            .background {
                ArrowlessPopoverPresenter(
                    isPresented: $isProjectSwitcherPresented,
                    preferredWidth: 320,
                    acceptsKeyboardInput: true,
                    content: AnyView(
                        HorizontalProjectSwitcher(isPresented: $isProjectSwitcherPresented)
                            .environment(appState)
                            .environment(projectStore)
                    )
                )
            }

            Divider()
                .frame(height: 18)

            if let workspace = activeWorkspace {
                HorizontalWorkspaceTabs(workspace: workspace, project: activeProject)
            } else {
                Spacer(minLength: 0)
            }

            Button {
                guard let projectID = appState.activeProjectID else { return }
                appState.createTab(projectID: projectID, projects: projectStore.projects)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .horizontalNewTabMaterial(isHovering: isNewTabHovering)
            .onHover { isNewTabHovering = $0 }
            .fixedSize()
            .layoutPriority(2)
            .help("New Tab")
            .disabled(appState.activeProjectID == nil)
        }
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 32)
    }
}

/// AppKit title-bar accessory that gives the horizontal tab strip the full row instead of toolbar overflow.
struct HorizontalTabBarAccessory: NSViewRepresentable {
    @Environment(AppState.self)
    private var appState
    @Environment(ProjectStore.self)
    private var projectStore
    let isPresented: Bool
    let availableWidth: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ marker: NSView, context: Context) {
        let requestedWidth = availableWidth.isFinite ? max(280, availableWidth - 92) : 800
        let rootView = AnyView(
            HorizontalTabBar()
                .frame(width: requestedWidth)
                // The old implementation added a fixed +9pt offset to
                // compensate for macOS 26's NSTitlebarAccessoryClipView
                // placing a `.left` accessory above the traffic-light center.
                // macOS 27 uses NSTitlebarAccessoryContainerView instead, so
                // that compensation over-shoots. Centering a 32pt row in the
                // measured title-bar host works on both systems.
                .frame(maxHeight: .infinity, alignment: .center)
                .environment(appState)
                .environment(projectStore)
        )
        context.coordinator.scheduleSync(
            marker: marker,
            rootView: rootView,
            isPresented: isPresented,
            availableWidth: availableWidth
        )
    }

    static func dismantleNSView(_ marker: NSView, coordinator: Coordinator) {
        _ = marker
        coordinator.removeAccessory()
    }

    @MainActor
    final class Coordinator {
        private struct AccessorySyncRequest {
            let rootView: AnyView
            let isPresented: Bool
            let availableWidth: CGFloat
            let revision: Int
        }

        private var revision = 0
        private weak var installedWindow: NSWindow?
        private var accessoryController: NSTitlebarAccessoryViewController?
        private var hostingView: HorizontalTabBarHostingView?

        func scheduleSync(
            marker: NSView,
            rootView: AnyView,
            isPresented: Bool,
            availableWidth: CGFloat
        ) {
            revision += 1
            let request = AccessorySyncRequest(
                rootView: rootView,
                isPresented: isPresented,
                availableWidth: availableWidth,
                revision: revision
            )
            syncWhenAttached(
                marker: marker,
                request: request,
                attempt: 0
            )
        }

        private func syncWhenAttached(
            marker: NSView,
            request: AccessorySyncRequest,
            attempt: Int
        ) {
            DispatchQueue.main.async { [weak self, weak marker] in
                guard let self, self.revision == request.revision, let marker else { return }
                guard let window = marker.window else {
                    guard attempt < 30 else { return }
                    self.syncWhenAttached(
                        marker: marker,
                        request: request,
                        attempt: attempt + 1
                    )
                    return
                }

                guard request.isPresented else {
                    self.removeAccessory()
                    return
                }
                self.installAccessory(
                    rootView: request.rootView,
                    in: window,
                    availableWidth: request.availableWidth
                )
            }
        }

        private func installAccessory(rootView: AnyView, in window: NSWindow, availableWidth: CGFloat) {
            if installedWindow !== window {
                removeAccessory()
            }

            let hostingView: HorizontalTabBarHostingView
            let accessoryController: NSTitlebarAccessoryViewController
            if let existingHostingView = self.hostingView,
               let existingAccessoryController = self.accessoryController
            {
                hostingView = existingHostingView
                accessoryController = existingAccessoryController
                hostingView.rootView = rootView
            } else {
                hostingView = HorizontalTabBarHostingView(rootView: rootView)
                accessoryController = NSTitlebarAccessoryViewController()
                accessoryController.layoutAttribute = .left
                accessoryController.view = hostingView
                window.addTitlebarAccessoryViewController(accessoryController)
                self.hostingView = hostingView
                self.accessoryController = accessoryController
                installedWindow = window
            }

            let measuredWindowWidth = availableWidth.isFinite
                ? max(window.frame.width, availableWidth)
                : window.frame.width
            let titlebarHeight = measuredTitlebarHeight(for: window)
            let accessorySize = NSSize(
                width: max(280, measuredWindowWidth - 92),
                height: titlebarHeight
            )
            hostingView.frame = NSRect(origin: .zero, size: accessorySize)
            hostingView.autoresizingMask = [.height]
            accessoryController.preferredContentSize = accessorySize
        }

        /// The unified title bar is not a stable constant on macOS. The
        /// content view's safe-area inset tracks the current AppKit title-bar
        /// height (52pt on macOS 27), while the content-layout delta provides a
        /// fallback during the short period before safe-area propagation.
        private func measuredTitlebarHeight(for window: NSWindow) -> CGFloat {
            let safeAreaHeight = window.contentView?.safeAreaInsets.top ?? 0
            let layoutDelta = window.frame.height - window.contentLayoutRect.height
            let measuredHeight = max(safeAreaHeight, layoutDelta)
            return measuredHeight.isFinite ? max(32, measuredHeight) : 32
        }

        func removeAccessory() {
            if let window = installedWindow,
               let accessoryController,
               let index = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessoryController })
            {
                window.removeTitlebarAccessoryViewController(at: index)
            }
            installedWindow = nil
            accessoryController = nil
            hostingView = nil
        }
    }
}

/// Prevents title-bar mouse drags from winning over horizontal tab reordering.
private final class HorizontalTabBarHostingView: NSHostingView<AnyView> {
    override var mouseDownCanMoveWindow: Bool { false }
}
