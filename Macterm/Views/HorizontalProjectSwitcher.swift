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
                        projectButton(PinnedTabs.project) {
                            appState.selectPinnedProject()
                        }
                    }

                    ForEach(filteredProjects) { project in
                        projectButton(project) {
                            appState.selectProject(project)
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
                Label("New Project", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .padding(10)
        .frame(width: 320)
        .horizontalPopoverSurface()
        .onAppear { searchIsFocused = true }
    }

    private var matchesPinnedProject: Bool {
        query.isEmpty || PinnedTabs.project.name.localizedStandardContains(query)
    }

    private func projectButton(_ project: Project, action: @escaping () -> Void) -> some View {
        Button {
            action()
            isPresented = false
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
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                if appState.activeProjectID == project.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(MactermTheme.accent)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
