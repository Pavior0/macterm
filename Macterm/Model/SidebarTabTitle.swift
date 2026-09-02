import Foundation

/// Formats automatic sidebar titles with project-relative working directories.
enum SidebarTabTitle {
    static func automaticTitle(
        activityTitle: String,
        foregroundIsShell: Bool,
        workingDirectory: String,
        projectDirectory: String
    ) -> String {
        guard let directory = projectRelativeDirectoryLabel(
            workingDirectory: workingDirectory,
            projectDirectory: projectDirectory
        )
        else { return activityTitle }

        if foregroundIsShell { return directory }
        return "\(directory) · \(activityTitle)"
    }

    /// Returns nil at the project root because the project header already names it.
    static func projectRelativeDirectoryLabel(
        workingDirectory: String,
        projectDirectory: String
    ) -> String? {
        let workingDirectory = ProjectPath.canonicalLocal(workingDirectory)
        let projectDirectory = ProjectPath.canonicalLocal(projectDirectory)
        guard workingDirectory != projectDirectory else { return nil }

        if let relativePath = descendantPath(workingDirectory, below: projectDirectory) {
            return compactRelativePath(relativePath)
        }

        let projectParent = (projectDirectory as NSString).deletingLastPathComponent
        if workingDirectory == projectParent { return ".." }
        if projectParent != projectDirectory,
           let siblingPath = descendantPath(workingDirectory, below: projectParent)
        {
            return compactSiblingPath(siblingPath)
        }

        return compactExternalPath(ProjectPath.homeContracted(workingDirectory))
    }

    private static func descendantPath(_ path: String, below parent: String) -> String? {
        let prefix = parent == "/" ? "/" : parent + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }

    private static func compactRelativePath(_ path: String) -> String {
        let components = path.split(separator: "/")
        guard components.count > 3 else { return path }
        return "…/" + components.suffix(3).joined(separator: "/")
    }

    private static func compactSiblingPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        guard components.count > 4, let sibling = components.first else { return "../" + path }
        return "../\(sibling)/…/" + components.suffix(2).joined(separator: "/")
    }

    private static func compactExternalPath(_ path: String) -> String {
        let prefix: String
        let remainder: Substring
        if path.hasPrefix("~/") {
            prefix = "~/"
            remainder = path.dropFirst(2)
        } else if path.hasPrefix("/") {
            prefix = "/"
            remainder = path.dropFirst()
        } else {
            return path
        }

        let components = remainder.split(separator: "/")
        guard components.count > 3 else { return path }
        return prefix + "…/" + components.suffix(2).joined(separator: "/")
    }
}
