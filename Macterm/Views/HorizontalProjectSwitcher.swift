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
    @FocusState
    private var searchIsFocused: Bool

    private var filteredProjects: [Project] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return projectStore.projects }
        return projectStore.projects.filter {
            $0.name.localizedStandardContains(needle) || $0.path.localizedStandardContains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
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

            ScrollView {
                LazyVStack(spacing: 2) {
                    if !appState.pinnedRecords.isEmpty, matchesPinnedProject {
                        HorizontalProjectSwitcherRow(
                            project: PinnedTabs.project,
                            isSelected: appState.activeProjectID == PinnedTabs.projectID
                        ) {
                            appState.selectPinnedProject()
                            isPresented = false
                        }
                    }

                    ForEach(filteredProjects) { project in
                        HorizontalProjectSwitcherRow(
                            project: project,
                            isSelected: appState.activeProjectID == project.id
                        ) {
                            appState.selectProject(project)
                            isPresented = false
                        }
                    }

                    if filteredProjects.isEmpty, !matchesPinnedProject {
                        ContentUnavailableView.search(text: query)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
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
        .onAppear { searchIsFocused = true }
    }

    private var matchesPinnedProject: Bool {
        query.isEmpty || PinnedTabs.project.name.localizedStandardContains(query)
    }
}

private struct HorizontalProjectSwitcherRow: View {
    let project: Project
    let isSelected: Bool
    let action: () -> Void
    @State
    private var isHovering = false

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
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(MactermTheme.accent)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .horizontalNavigationStateSurface(isHovering: isHovering, isSelected: isSelected)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
