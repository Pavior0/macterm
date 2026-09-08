import AppKit

/// Tells pointer-driven selection changes apart from keyboard-driven ones in a
/// list that both lets hover select a row and scrolls the keyboard's selection
/// into view — the command palette and the tab switcher.
///
/// Both need the same two rules. A hovered row must not be scrolled into view:
/// it is under the pointer, so it is already visible, and centering it would
/// slide the list away under the cursor onto the next row, which hovers in
/// turn. And a row that arrives under a *stationary* pointer because the list
/// scrolled is not a hover: AppKit re-evaluates tracking areas after a scroll,
/// so the row that lands under the cursor reports entry as if the pointer had
/// moved onto it, which would let whatever the scroll put under the pointer
/// override the keyboard step that caused the scroll.
///
/// The hover request is remembered by value rather than as a one-shot flag, so
/// a hover that changes nothing (the row was already selected, or the view
/// compared against a stale selection) cannot arm the suppression for the
/// next keyboard step.
///
/// A class rather than value state on purpose: it is written from hover
/// handlers on every pointer move, and a `@State` write would invalidate the
/// whole list each time. Hold it in `@State` so SwiftUI keeps one instance per
/// view identity.
@MainActor
final class HoverSelectionTracker {
    private var pointerLocation: CGPoint?
    private var hoverRequest: Int?

    /// Whether a hover over `index` should select it. False when the pointer
    /// has not moved since the last accepted hover — content moved under it —
    /// or when `index` is already `current`. Remembers an accepted request so
    /// `isHoverSelection` can recognize the change it produces.
    func noteHover(over index: Int, current: Int) -> Bool {
        let location = NSEvent.mouseLocation
        guard location != pointerLocation else { return false }
        pointerLocation = location
        guard index != current else { return false }
        hoverRequest = index
        return true
    }

    /// Whether a selection change to `index` is the one hover asked for — the
    /// caller should not scroll for it. Every change clears the request, so a
    /// request that never landed cannot suppress a later keyboard step.
    func isHoverSelection(_ index: Int) -> Bool {
        defer { hoverRequest = nil }
        return hoverRequest == index
    }
}
