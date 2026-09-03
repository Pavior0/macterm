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
    private var isNewProjectHovered = false
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
                HStack(spacing: 7) {
                    Label("New Project", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .frame(height: 30, alignment: .leading)
                .horizontalProjectMenuHoverMaterial(isHovering: isNewProjectHovered)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            // The system default Menu style becomes a large glass capsule on
            // macOS 27. Keep this footer quiet and let its hover state provide
            // the only transient surface.
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .onHover { isNewProjectHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isNewProjectHovered)
        }
        .padding(10)
        .frame(width: 320)
        // The panel window already provides the floating separation. Avoid a
        // second Liquid Glass edge here; it reads as a dark halo around the
        // project list instead of a clean popover boundary.
        .horizontalPopoverSurface(showsGlassEdge: false)
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
                            .foregroundStyle(.primary.opacity(0.68))
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

private extension View {
    /// Keep the footer quiet until the pointer reaches it. On macOS 26 and
    /// later, regular Liquid Glass supplies the adaptive edge and contrast;
    /// older systems get the nearest local-material treatment instead.
    @ViewBuilder
    func horizontalProjectMenuHoverMaterial(isHovering: Bool) -> some View {
        if isHovering {
            if #available(macOS 26.0, *) {
                glassEffect(.regular, in: .rect(cornerRadius: 8))
            } else {
                background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                    }
            }
        } else {
            self
        }
    }
}
