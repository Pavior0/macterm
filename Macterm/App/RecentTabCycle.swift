import Foundation

/// One frozen-MRU Recent Tab interaction.
struct RecentTabCycle {
    let projectID: UUID
    let tabIDs: [UUID]
    let originalTabID: UUID
    let showsSwitcher: Bool
    var selectedIndex: Int

    var selectedTabID: UUID { tabIDs[selectedIndex] }
}
