import AppKit
import SwiftUI

// MARK: - Overlay

/// Transient tab switcher shown while the Recent Tab shortcut is held (#344).
///
/// Deliberately not the command palette: the palette is a search surface with
/// a text field and a focus handoff, while this is a heads-up display for a
/// gesture that starts and ends inside one key-hold. It shares the palette's
/// chrome (`glassPanel`) so the two read as the same family of floating
/// surfaces, but not its scrim — the gesture is over in under a second, and
/// dimming the window the user is switching *within* hides the very thing
/// they are choosing between.
///
/// The panel takes the pointer: hovering a card moves the selection, clicking
/// one commits to it. Only the panel does — nothing else in the overlay draws
/// a background, so presses outside it fall through to the terminal
/// underneath. Note that a click here is necessarily a *modifier*-click, since
/// releasing the modifier is what ends the gesture.
///
/// With the strip up, cycling moves the selection only — the tab behind it and
/// the pane holding focus stay put until the modifier is released (see
/// `AppState.cycleRecentTab`). So the strip is the whole interface for the
/// gesture: it has to show where the next press lands, not just confirm where
/// the last one did.
/// One tab in the strip: where it sits in the cycle, its 1-based number in
/// the workspace (what the numbered tab icons show), and the tab itself.
struct TabSwitcherEntry {
    let index: Int
    let number: Int
    let tab: TerminalTab
}

struct TabSwitcherOverlay: View {
    @Environment(AppState.self)
    private var appState

    var body: some View {
        if let workspace = activeWorkspace, appState.tabCycleTabIDs.count > 1 {
            let entries = tabs(in: workspace)
            GeometryReader { geo in
                TabSwitcherStrip(
                    entries: entries,
                    selection: appState.tabCycleSelection,
                    availableWidth: geo.size.width,
                    availableHeight: geo.size.height,
                    paneAspect: appState.paneContainerAspect,
                    onHover: { appState.focusTabCycle(at: $0) },
                    onClick: { index in
                        guard let projectID = appState.activeProjectID else { return }
                        appState.commitTabCycle(projectID: projectID, at: index)
                    }
                )
                // Centered: the strip is the whole interface for the gesture
                // (the window behind it does not change until release), so it
                // belongs where the eye already is rather than tucked at an
                // edge — and centering is also what makes it a plausible
                // pointer target.
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .transition(.opacity)
        }
    }

    private var activeWorkspace: Workspace? {
        guard let pid = appState.activeProjectID else { return nil }
        return appState.workspaces[pid]
    }

    /// The cycle order resolved to live tabs, dropping any that closed
    /// mid-gesture so the strip can't render a hole. Each entry carries the
    /// tab's own 1-based position in the workspace too, because the numbered
    /// icon variants show that number — not the tab's place in the cycle.
    private func tabs(in workspace: Workspace) -> [TabSwitcherEntry] {
        appState.tabCycleTabIDs.enumerated().compactMap { index, id in
            guard let position = workspace.tabs.firstIndex(where: { $0.id == id }) else { return nil }
            return TabSwitcherEntry(index: index, number: position + 1, tab: workspace.tabs[position])
        }
    }
}

// MARK: - Strip

/// The cards themselves, wrapped into centered rows when the cycle order no
/// longer fits the window. How many fit is asked of the window rather than
/// hardcoded, so a wide window shows more of the order and a narrow one still
/// shows a readable card.
private struct TabSwitcherStrip: View {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    let entries: [TabSwitcherEntry]
    let selection: Int
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    /// Width over height of the region the panes actually fill, so cards are
    /// shaped like the thing they picture. nil before anything was measured.
    let paneAspect: CGFloat?
    /// Pointer handlers, both taking a card's index in the cycle order.
    let onHover: (Int) -> Void
    let onClick: (Int) -> Void

    private static let spacing: CGFloat = 10
    /// Inset from the panel's edge to the cards. The preview inside a card
    /// carries `TabSwitcherCard.selectionHalo` on top of this, so the gap the
    /// eye actually reads — panel edge to picture — is the sum, equally on
    /// every side. Anything that pads one axis and not the other shows up
    /// immediately here: the card used to carry a stray `.padding(.vertical, 2)`
    /// (left over from a uniform padding that was removed around it), which
    /// made the top gap 20 against 18 at the sides.
    private static let insets: CGFloat = 14
    /// Clear space between the panel and the window edges.
    private static let windowMargin: CGFloat = 48

    @State
    private var selectionChangedFromHover = false

    var body: some View {
        let cardWidth = TabSwitcherCard.width(forPaneAspect: paneAspect)
        let rows = wrappedRows(cardWidth: cardWidth)
        let maximumPanelHeight = max(0, availableHeight - Self.windowMargin * 2)

        ViewThatFits(in: .vertical) {
            cardRows(rows)
                .padding(Self.insets)
                .glassPanel()

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    cardRows(rows)
                        .padding(Self.insets)
                }
                .scrollIndicators(.visible)
                .onChange(of: selection) { _, index in
                    guard !selectionChangedFromHover else {
                        selectionChangedFromHover = false
                        return
                    }
                    guard let rowIndex = rows.firstIndex(where: { row in
                        row.contains(where: { $0.index == index })
                    })
                    else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                        proxy.scrollTo(rowIndex, anchor: .center)
                    }
                }
            }
            .glassPanel()
        }
        .frame(height: maximumPanelHeight)
    }

    private func cardRows(_ rows: [[TabSwitcherEntry]]) -> some View {
        VStack(spacing: Self.spacing) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: Self.spacing) {
                    ForEach(rows[rowIndex], id: \.tab.id) { entry in
                        TabSwitcherCard(
                            tab: entry.tab,
                            number: entry.number,
                            isSelected: entry.index == selection,
                            paneAspect: paneAspect
                        )
                        .onHover { hovering in
                            guard hovering, entry.index != selection else { return }
                            selectionChangedFromHover = true
                            onHover(entry.index)
                        }
                        .onTapGesture { onClick(entry.index) }
                    }
                }
                .id(rowIndex)
            }
        }
    }

    private func wrappedRows(cardWidth: CGFloat) -> [[TabSwitcherEntry]] {
        let rowCapacity = rowCapacity(for: availableWidth, cardWidth: cardWidth)
        return stride(from: 0, to: entries.count, by: rowCapacity).map { start in
            Array(entries[start ..< min(start + rowCapacity, entries.count)])
        }
    }

    /// How many complete cards fit in one row, always at least one.
    private func rowCapacity(for width: CGFloat, cardWidth: CGFloat) -> Int {
        let chrome = Self.windowMargin * 2 + Self.insets * 2
        let perCard = cardWidth + Self.spacing
        let fits = Int(((width - chrome + Self.spacing) / perCard).rounded(.down))
        return max(1, fits)
    }
}

// MARK: - Card

/// One tab: a miniature of its split layout with each pane's own preview and
/// name, over the tab's title row.
private struct TabSwitcherCard: View {
    let tab: TerminalTab
    /// The tab's 1-based number in the workspace, for the numbered tab icons.
    let number: Int
    let isSelected: Bool
    let paneAspect: CGFloat?

    /// Height of the preview at a comfortably wide pane region. A narrow
    /// (portrait) one grows TALLER instead of the card growing wider than its
    /// picture — see `previewHeight(forPaneAspect:)`.
    private static let basePreviewHeight: CGFloat = 140
    /// Ceiling on that growth, so an extremely tall pane region can't turn the
    /// strip into a wall.
    private static let maxPreviewHeight: CGFloat = 190
    /// Width a narrow card is grown toward — enough to carry an icon and some
    /// title. Reached by making the preview taller, NEVER by padding the card
    /// wider than its picture: a card with surplus width has to distribute it,
    /// and centering that surplus is what made the side padding drift away
    /// from the top padding as the window changed shape.
    private static let widthTarget: CGFloat = 116
    /// Aspect assumed before anything has been measured. Only reachable for a
    /// workspace whose panes have never been on screen this run.
    static let fallbackAspect: CGFloat = 16.0 / 10.0
    private static let cornerRadius: CGFloat = 8
    /// Halo left around the preview for the selection fill to show in. Zero
    /// would hide it: the thumbnail is opaque, so a highlight exactly the
    /// preview's size sits entirely behind it.
    private static let selectionHalo: CGFloat = 4

    /// Aspect to lay out at, floored so a degenerate measurement can't divide
    /// the height into something enormous.
    private static func safeAspect(_ aspect: CGFloat?) -> CGFloat {
        max(aspect ?? fallbackAspect, 0.2)
    }

    /// Preview height for a pane region: the base, grown toward `widthTarget`
    /// when the region is narrow, capped.
    static func previewHeight(forPaneAspect aspect: CGFloat?) -> CGFloat {
        min(maxPreviewHeight, max(basePreviewHeight, widthTarget / safeAspect(aspect)))
    }

    /// The card's width — exactly its preview plus the halo, at every aspect.
    /// Keeping the two equal is what makes the panel's padding uniform by
    /// construction: there is no surplus for a layout to distribute.
    static func width(forPaneAspect aspect: CGFloat?) -> CGFloat {
        (previewHeight(forPaneAspect: aspect) * safeAspect(aspect)).rounded() + selectionHalo * 2
    }

    private var cardWidth: CGFloat { Self.width(forPaneAspect: paneAspect) }

    var body: some View {
        // Preview, title row and card are all exactly `cardWidth`: the preview
        // because the card's width is derived from it, the title row because
        // it asks for the same. Nothing here is wider than its content, so
        // there is no surplus to center and the panel's padding reads the same
        // on every side at every window shape.
        VStack(alignment: .leading, spacing: 6) {
            PaneMosaic(node: tab.splitRoot, focusedPaneID: tab.focusedPaneID)
                // The mosaic gets the pane region's real proportions, so every
                // leaf inside it gets its own pane's proportions and the
                // captured frames drop in uncropped.
                .aspectRatio(Self.safeAspect(paneAspect), contentMode: .fit)
                .frame(height: Self.previewHeight(forPaneAspect: paneAspect))
                // The gaps between leaves are the miniature split dividers, so
                // they need a color of their own. Left transparent they showed
                // whatever sat behind the card — the selection fill on the
                // selected one, the glass panel on the rest — which made two
                // cards of the same layout read as different things.
                .background(MactermTheme.border)
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .strokeBorder(MactermTheme.border.opacity(0.6), lineWidth: 1)
                )
                // The selection is a fill hugging the PREVIEW, evenly on all
                // four sides and concentric with its corner, rather than a
                // stroke around the whole card. A card-sized box was the wrong
                // shape for it: the preview takes the pane region's aspect, so
                // on a portrait window it sits well inside a card widened to
                // hold the title, and the highlight framed empty panel instead
                // of the picture.
                .padding(Self.selectionHalo)
                .background(
                    RoundedRectangle(
                        cornerRadius: Self.cornerRadius + Self.selectionHalo,
                        style: .continuous
                    )
                    .fill(isSelected ? MactermTheme.fg.opacity(0.14) : .clear)
                )

            HStack(spacing: 6) {
                // The sidebar's own glyph, preferences and all — the chosen
                // tab icon, the agent logo in its brand color, the running
                // spinner and the done dot. An earlier cut drew a hardcoded
                // terminal symbol and its own spinner here, so three of the
                // four preferences behind it did nothing on these cards.
                // Deliberately unframed: when the preferences leave nothing
                // to draw it contributes no view and no spacing, and the
                // title stays flush with the preview's edge.
                // Tinted with the title, so the whole row brightens on the
                // selected card rather than a white title beside a dim icon.
                TabGlyph(
                    tab: tab,
                    index: number,
                    tint: isSelected ? MactermTheme.fg : MactermTheme.fgMuted
                )
                Text(tab.sidebarRowTitle)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? MactermTheme.fg : MactermTheme.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            // Inset by the halo so the icon's leading edge lands on the
            // preview's own edge rather than the highlight's.
            .padding(.horizontal, Self.selectionHalo)
            .frame(width: cardWidth, alignment: .leading)
        }
    }
}

// MARK: - Pane mosaic

/// The tab's split tree, laid out at card scale with the branches' real
/// ratios, so a 2x2 grid looks like a 2x2 grid. Each leaf renders its frozen
/// preview with the pane's name over it.
private struct PaneMosaic: View {
    let node: SplitNode
    let focusedPaneID: UUID?

    /// Gap between panes — the miniature of the split divider. Enough to read
    /// as a division at this scale without eating the previews.
    private static let gap: CGFloat = 2

    var body: some View {
        switch node {
        case let .pane(pane):
            PaneMosaicLeaf(pane: pane, isFocused: pane.id == focusedPaneID)
        case let .split(branch):
            GeometryReader { geo in
                let ratio = min(max(branch.ratio, 0.05), 0.95)
                switch branch.direction {
                case .horizontal:
                    let first = max(0, (geo.size.width - Self.gap) * ratio)
                    HStack(spacing: Self.gap) {
                        PaneMosaic(node: branch.first, focusedPaneID: focusedPaneID)
                            .frame(width: first)
                        PaneMosaic(node: branch.second, focusedPaneID: focusedPaneID)
                    }
                case .vertical:
                    let first = max(0, (geo.size.height - Self.gap) * ratio)
                    VStack(spacing: Self.gap) {
                        PaneMosaic(node: branch.first, focusedPaneID: focusedPaneID)
                            .frame(height: first)
                        PaneMosaic(node: branch.second, focusedPaneID: focusedPaneID)
                    }
                }
            }
        }
    }
}

private struct PaneMosaicLeaf: View {
    let pane: Pane
    let isFocused: Bool

    @Environment(AppState.self)
    private var appState

    var body: some View {
        let preview = appState.panePreviews[pane.id]
        // The pane's background is what defines this leaf's size. The preview
        // goes in an `overlay`, never in the layout: a `resizable` image sized
        // `.fill` reports its own (full-frame) dimensions, so as a ZStack child
        // it grew the leaf past its frame and carried the name chip out of the
        // clipped area with it — the chips were being drawn below the card.
        Rectangle()
            .fill(Color(nsColor: preview?.background ?? MactermTheme.nsBg))
            .overlay(alignment: .topLeading) {
                if let image = preview?.image {
                    // `.fit`, never `.fill`: the leaf's box already has this
                    // pane's real proportions (the mosaic is laid out at the
                    // pane region's aspect), so the frame lands in it whole.
                    // Cropping here is what made an earlier cut of this show
                    // only the top half of every tall pane.
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .clipped()
            // The focused pane is marked the way the split view marks it: the
            // others are dimmed rather than this one being highlighted.
            .overlay(isFocused ? Color.clear : Color.black.opacity(0.22))
    }
}
