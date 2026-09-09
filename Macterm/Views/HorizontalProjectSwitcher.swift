import AppKit
import SwiftUI

// Searchable project picker presented from the horizontal title-bar indicator.

struct HorizontalProjectSwitcher: View {
    @Environment(AppState.self)
    private var appState
    @Environment(ProjectStore.self)
    private var projectStore
    @Binding
    var isPresented: Bool
    @State
    private var query = ""
    @State
    private var isNewProjectHovering = false
    @State
    private var highlightedProjectID: UUID?
    @FocusState
    private var searchIsFocused: Bool

    private var searchNeedle: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedProjects: [Project] {
        let needle = searchNeedle
        let storedProjects: [Project] = if needle.isEmpty {
            projectStore.projects
        } else {
            projectStore.projects.filter {
                $0.name.localizedStandardContains(needle) || $0.path.localizedStandardContains(needle)
            }
        }
        let includesPinnedProject = !appState.pinnedRecords.isEmpty
            && (needle.isEmpty || PinnedTabs.project.name.localizedStandardContains(needle))
        return includesPinnedProject ? [PinnedTabs.project] + storedProjects : storedProjects
    }

    var body: some View {
        let projects = displayedProjects
        return VStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search projects", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchIsFocused)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(projects) { project in
                            HorizontalProjectSwitcherRow(
                                project: project,
                                isCurrentProject: appState.activeProjectID == project.id,
                                isHighlighted: highlightedProjectID == project.id,
                                onHover: {
                                    highlightedProjectID = project.id
                                },
                                action: {
                                    selectProject(project)
                                }
                            )
                            .id(project.id)
                        }

                        if projects.isEmpty {
                            ContentUnavailableView.search(text: query)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        }
                    }
                }
                .onChange(of: highlightedProjectID) { _, projectID in
                    guard let projectID else { return }
                    proxy.scrollTo(projectID, anchor: .center)
                }
            }
            .frame(maxHeight: 320)

            Divider()

            Menu {
                Button("Local Folder…") {
                    isPresented = false
                    _ = appState.openProject(store: projectStore)
                }
                Button("Remote Machine…") {
                    isPresented = false
                    appState.isNewRemoteProjectSheetPresented = true
                }
            } label: {
                HStack(spacing: 7) {
                    Label("New Project", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .frame(height: 30, alignment: .leading)
                .horizontalNavigationStateSurface(isHovering: isNewProjectHovering)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .onHover { isNewProjectHovering = $0 }
        }
        .padding(10)
        .frame(width: 320)
        .horizontalPopoverSurface()
        .onAppear {
            resetHighlightedProject(in: projects, preferCurrentProject: true)
            DispatchQueue.main.async { searchIsFocused = true }
        }
        .onChange(of: query) {
            resetHighlightedProject(in: projects, preferCurrentProject: false)
        }
        .onChange(of: projects) { _, projects in
            if highlightedProjectID.map({ id in projects.contains { $0.id == id } }) != true {
                resetHighlightedProject(in: projects, preferCurrentProject: false)
            }
        }
        .onKeyPress(keys: [.upArrow], phases: [.down, .repeat]) { _ in
            moveProjectHighlight(by: -1, in: projects)
            return .handled
        }
        .onKeyPress(keys: [.downArrow], phases: [.down, .repeat]) { _ in
            moveProjectHighlight(by: 1, in: projects)
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "p"), phases: [.down, .repeat]) { press in
            guard press.modifiers == .control else { return .ignored }
            moveProjectHighlight(by: -1, in: projects)
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "n"), phases: [.down, .repeat]) { press in
            guard press.modifiers == .control else { return .ignored }
            moveProjectHighlight(by: 1, in: projects)
            return .handled
        }
        .onKeyPress(.return) {
            activateHighlightedProject(in: projects)
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    /// Moves the project switcher's keyboard highlight, wrapping at both ends.
    private func moveProjectHighlight(by offset: Int, in projects: [Project]) {
        guard !projects.isEmpty else {
            highlightedProjectID = nil
            return
        }
        guard let selectedID = highlightedProjectID,
              let selectedIndex = projects.firstIndex(where: { $0.id == selectedID })
        else {
            highlightedProjectID = offset < 0 ? projects.last?.id : projects.first?.id
            return
        }
        let nextIndex = (selectedIndex + offset + projects.count) % projects.count
        highlightedProjectID = projects[nextIndex].id
    }

    private func resetHighlightedProject(in projects: [Project], preferCurrentProject: Bool) {
        if preferCurrentProject,
           let activeProjectID = appState.activeProjectID,
           projects.contains(where: { $0.id == activeProjectID })
        {
            highlightedProjectID = activeProjectID
        } else {
            highlightedProjectID = projects.first?.id
        }
    }

    private func activateHighlightedProject(in projects: [Project]) {
        guard let highlightedProjectID,
              let project = projects.first(where: { $0.id == highlightedProjectID })
        else { return }
        selectProject(project)
    }

    private func selectProject(_ project: Project) {
        if project.id == PinnedTabs.projectID {
            appState.selectPinnedProject()
        } else {
            appState.selectProject(project)
        }
        isPresented = false
    }
}

private struct HorizontalProjectSwitcherRow: View {
    let project: Project
    let isCurrentProject: Bool
    let isHighlighted: Bool
    let onHover: () -> Void
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: project.id == PinnedTabs.projectID ? "pin" : (project.isRemote ? "network" : "folder"))
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name)
                        .lineLimit(1)
                    if project.id != PinnedTabs.projectID {
                        Text(project.path)
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.68))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                if isCurrentProject {
                    Image(systemName: "checkmark")
                        .foregroundStyle(MactermTheme.accent)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .horizontalNavigationStateSurface(isHovering: false, isSelected: isHighlighted)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { onHover() }
        }
    }
}
