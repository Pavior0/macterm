import AppKit
import SwiftUI

// MARK: - Overlay

/// Transient tab switcher shown while the Recent Tab shortcut is held (#344).
///
/// Deliberately not the command palette: the palette is a search surface with
/// a text field and a focus handoff, while this is a heads-up display for a
/// gesture that starts and ends inside one key-hold. It shares the palette's
/// glass material (`glassPanelBackground`) so the two read as the same family
/// of floating surfaces, but not its border-and-shadow layer — which in this
/// standalone panel read as a dark ring — nor its scrim: the gesture is over
/// in under a second, and dimming the window the user is switching *within*
/// hides the very thing they are choosing between.
///
/// The strip takes the pointer: hovering a card moves the selection, clicking
/// one commits to it, and a press anywhere outside the panel cancels the
/// gesture (and is swallowed, so it doesn't also reach the terminal). Note
/// that a click here is necessarily a *modifier*-click, since releasing the
/// modifier is what ends the gesture.
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
            TabSwitcherPanelPresenter(
                // The strip renders in its own NSHostingView — a NEW SwiftUI
                // root — and environment values do not travel with a view
                // VALUE, only down a rendered tree. Without re-injecting
                // AppState here, PaneMosaicLeaf's `@Environment(AppState.self)`
                // finds nothing and the hosting view crashes the app on its
                // first layout (the same reason HorizontalTabBar re-injects
                // its stores into ArrowlessPopover content).
                content: TabSwitcherStrip(
                    entries: entries,
                    selection: appState.tabCycleSelection,
                    onHover: { appState.focusTabCycle(at: $0) },
                    onClick: { index in
                        guard let projectID = appState.activeProjectID else { return }
                        appState.commitTabCycle(projectID: projectID, at: index)
                    }
                )
                .environment(appState),
                contentWidth: TabSwitcherStrip.width(for: entries.count),
                onCancel: { appState.cancelTabCycle() }
            )
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

// MARK: - Floating panel

/// Presents the strip in its own borderless panel, centered on the terminal
/// window.
///
/// The separate window is the point: an NSWindow only ever shows content
/// inside its own frame, so a strip wider than the terminal window — many
/// candidates, or a narrow window — mounted as an in-window overlay would be
/// clipped by the window it floats over. In its own window it extends past
/// the terminal's edges, clamped only by the screen (the way Arc's tab
/// switcher overflows its window).
///
/// The panel never becomes key: the terminal window keeps keyboard focus for
/// the whole gesture, so the modifier-release commit and the Escape cancel
/// keep flowing through the app's normal key routing while the strip is up.
/// A click outside the panel cancels the gesture and is swallowed — a stray
/// press during a sub-second gesture should dismiss the switcher, not reach
/// through it into the terminal. (Clicks on other apps' windows never reach
/// this monitor, so those leave the gesture to end on its own terms.)
private struct TabSwitcherPanelPresenter<Content: View>: NSViewRepresentable {
    let content: Content
    /// The strip's computed width (see `TabSwitcherStrip.width(for:)`). The
    /// panel's height is MEASURED from the laid-out content in `present` —
    /// the width has to come from constants because the hosting view needs a
    /// width proposal before its layout exists to measure.
    let contentWidth: CGFloat
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        let coordinator = context.coordinator
        // `updateNSView` can run before SwiftUI inserts the view into the
        // window's hierarchy, when there is no window to center on yet —
        // retry the presentation once one exists.
        view.onWindowAttached = { [weak coordinator, weak view] in
            guard let coordinator, let view else { return }
            coordinator.retryPresentation(anchorView: view)
        }
        return view
    }

    func updateNSView(_ anchorView: AnchorView, context: Context) {
        context.coordinator.update(
            anchorView: anchorView,
            content: content,
            contentWidth: contentWidth,
            onCancel: onCancel
        )
    }

    static func dismantleNSView(_ nsView: AnchorView, coordinator: Coordinator) {
        _ = nsView
        coordinator.dismiss()
    }

    @MainActor
    final class Coordinator {
        private var panel: TabSwitcherPanel?
        private var hostingView: NSHostingView<Content>?
        private var outsideClickMonitor: Any?
        private var onCancel: (() -> Void)?
        /// The latest content and width, kept so the window-attached retry can
        /// present them: `updateNSView` routinely runs BEFORE SwiftUI inserts
        /// the anchor into the window, when there is no window to center on
        /// yet — and without this the first press of the gesture presented
        /// nothing, leaving the switcher to appear only on the second press.
        private var content: Content?
        private var contentWidth: CGFloat?

        func update(
            anchorView: NSView,
            content: Content,
            contentWidth: CGFloat,
            onCancel: @escaping () -> Void
        ) {
            self.content = content
            self.contentWidth = contentWidth
            self.onCancel = onCancel
            guard let window = anchorView.window else { return }
            present(content, contentWidth: contentWidth, centeredOn: window)
        }

        /// The `makeNSView` retry path: the anchor landed in a window after
        /// the last `update` found none.
        func retryPresentation(anchorView: NSView) {
            guard let content, let contentWidth, let window = anchorView.window else { return }
            present(content, contentWidth: contentWidth, centeredOn: window)
        }

        private func present(_ content: Content, contentWidth: CGFloat, centeredOn window: NSWindow) {
            let panel = self.panel ?? makePanel()
            let hostingView = self.hostingView ?? NSHostingView(rootView: content)
            hostingView.rootView = content
            // Width proposed from constants, height measured after a layout
            // pass with that width in place — the ArrowlessPopoverPresenter
            // pattern. Measuring without the width proposal was the earlier
            // bug: glass-backed content answers a near-zero intrinsic size,
            // so the panel came up invisible on the first press.
            hostingView.frame.size.width = contentWidth
            hostingView.layoutSubtreeIfNeeded()
            let size = NSSize(width: contentWidth, height: max(1, hostingView.fittingSize.height))
            hostingView.frame = NSRect(origin: .zero, size: size)
            panel.contentView = hostingView
            panel.setContentSize(size)
            panel.setFrameOrigin(Self.centeredOrigin(size: size, in: window))
            self.panel = panel
            self.hostingView = hostingView

            guard !panel.isVisible else { return }
            installOutsideClickMonitor(panel: panel)
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.10
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }

        func dismiss() {
            if let outsideClickMonitor {
                NSEvent.removeMonitor(outsideClickMonitor)
            }
            outsideClickMonitor = nil
            panel?.orderOut(nil)
            panel = nil
            hostingView = nil
            onCancel = nil
        }

        private func makePanel() -> TabSwitcherPanel {
            let panel = TabSwitcherPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            // The window shadow IS the container's depth. A SwiftUI shadow
            // can't do this job: the window is exactly content-sized, so it
            // would clip at the window bounds (a straight cut through the
            // shadow band), and enlarging the window to give it room would
            // leave a dead transparent frame that swallows clicks. The
            // window-server shadow draws OUTSIDE the window, following the
            // glass's rounded shape — the way every borderless HUD
            // (Spotlight, the App Switcher) gets its lift. Deliberately not
            // ArrowlessPopoverPanel's macOS 26 `hasShadow = false`: that
            // popover is anchored to the tab bar, where the glass's own edge
            // plus the proximity already read as elevation, while this strip
            // floats mid-window over terminal content and reads pasted-on
            // without a shadow.
            panel.hasShadow = true
            panel.level = .floating
            panel.isMovable = false
            panel.animationBehavior = .none
            // NOT `.transient`: that makes the window vanish the moment the
            // app deactivates, which can happen DURING the gesture (an
            // overlapping app activating, or an automation tool fronting
            // something else) — the strip would blink out from under a still
            // held modifier and the release would commit blind. The overlay's
            // own dismissal paths (modifier release, Escape, outside click,
            // project switch) already own its lifetime.
            panel.collectionBehavior = [.fullScreenAuxiliary]
            return panel
        }

        /// Center the panel on the terminal window, clamped to the screen's
        /// visible frame — the window's edges are no longer the boundary, but
        /// the screen's still are. A strip wider than the screen pins left and
        /// loses its right end rather than centering off-screen on both.
        private static func centeredOrigin(size: NSSize, in window: NSWindow) -> NSPoint {
            let frame = window.frame
            var origin = NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2
            )
            let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
            origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
            origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
            return origin
        }

        private func installOutsideClickMonitor(panel: TabSwitcherPanel) {
            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                // Clicks on the panel itself reach the cards; anything else
                // the app would deliver cancels the gesture and is swallowed.
                guard event.window !== panel else { return event }
                self?.onCancel?()
                return nil
            }
        }
    }
}

/// Mount point that reports when it actually lands in a window (see
/// `TabSwitcherPanelPresenter.makeNSView`).
private final class AnchorView: NSView {
    var onWindowAttached: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onWindowAttached?() }
    }
}

/// The strip's borderless window. Never key, so the terminal window keeps
/// keyboard focus for the whole gesture.
private final class TabSwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Strip

/// The cards themselves — the whole cycle order in one fixed row, sized by
/// its content and centered on the window (Arc-style).
///
/// Not a viewport and not a scroll view: the panel's width is the content's
/// width, full stop. The strip lives in its own borderless window (see
/// `TabSwitcherPanelPresenter`), so a row wider than the terminal window
/// extends past the window's edges instead of being clipped by them —
/// clamped only by the screen. Sliding the row under a clip as the selection
/// moved read as horizontal scrolling, and reflowing the card size changed
/// the panel's width mid-gesture; symmetric overflow is the better failure.
private struct TabSwitcherStrip: View {
    let entries: [TabSwitcherEntry]
    let selection: Int
    /// Pointer handlers, both taking a card's index in the cycle order.
    let onHover: (Int) -> Void
    let onClick: (Int) -> Void

    private static let spacing: CGFloat = 10
    /// Inset from the panel's edge to the cards. The card's own padding
    /// carries the rest of the gap, so the distance the eye reads — panel
    /// edge to picture — is this plus `TabSwitcherCard.cardPadding`, equally
    /// on every side. Anything that pads one axis and not the other shows up
    /// immediately here: the card used to carry a stray `.padding(.vertical, 2)`
    /// (left over from a uniform padding that was removed around it), which
    /// made the top gap 20 against 18 at the sides.
    private static let insets: CGFloat = 14

    /// The strip's exact width for `entryCount` cards — computed, because the
    /// row is fully determined by its constants. The HEIGHT is not computed:
    /// it is measured with a width proposal (`layoutSubtreeIfNeeded` then
    /// `fittingSize.height`, the `ArrowlessPopoverPresenter` pattern), which
    /// is the only reliable way through a hosting view — glass-backed content
    /// reports a near-zero intrinsic size when asked without one.
    static func width(for entryCount: Int) -> CGFloat {
        let cards = CGFloat(max(entryCount, 1))
        return cards * TabSwitcherCard.cardWidth + (cards - 1) * spacing + insets * 2
    }

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(entries, id: \.tab.id) { entry in
                TabSwitcherCard(
                    tab: entry.tab,
                    number: entry.number,
                    isSelected: entry.index == selection
                )
                .onHover { if $0 { onHover(entry.index) } }
                .onTapGesture { onClick(entry.index) }
            }
        }
        .padding(Self.insets)
        // Bare glass, no stroke: the glass draws its own adaptive edge, and
        // the hairline border of `glassPanel` (the palette's recipe) stacked
        // on it read, in this standalone panel, as a dark ring around the
        // strip. The drop shadow is deliberately not here either — the window
        // is exactly content-sized, so a SwiftUI shadow would clip at its
        // bounds; the panel's WINDOW shadow provides the depth instead (see
        // `makePanel`).
        .glassPanelBackground(cornerRadius: GlassPanelMetrics.cornerRadius)
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

    /// One card shape at every window and pane aspect: fixed width, with the
    /// preview carrying a fixed 16:10 proportion (a screen-like shape — the
    /// same one this strip assumed before it could be measured at all).
    /// Nothing about the strip's geometry depends on the window, so the
    /// panel's width never changes mid-gesture. `PaneMosaic` still lays its
    /// leaves out by the split's real ratios; captured frames letterbox
    /// `.fit` inside their leaves instead of dictating the card.
    static let cardWidth: CGFloat = 160
    private static let previewAspect: CGFloat = 16.0 / 10.0
    /// Padding inside the card, around the preview and the title row. With the
    /// full-card selection fill (below) this is also the fill's inset from the
    /// card's rounded edge, so the selected card reads as one surface behind
    /// both its picture and its title.
    private static let cardPadding: CGFloat = 7
    private static let previewCornerRadius: CGFloat = 8
    private static let cardCornerRadius: CGFloat = 10

    /// The preview area: the card minus its padding, at the fixed aspect.
    /// Exactly this wide, so the title row can ask for the same width and
    /// nothing in the card is wider than its content — the #347
    /// uniform-padding invariant.
    private static var previewSize: CGSize {
        let width = cardWidth - cardPadding * 2
        return CGSize(width: width, height: width / previewAspect)
    }

    private var paneCount: Int { tab.splitRoot.allPanes().count }

    var body: some View {
        // Preview, title row and card are all exactly `cardWidth`: the preview
        // because the card's width is derived from it, the title row because
        // it asks for the same. Nothing here is wider than its content, so
        // there is no surplus to center and the panel's padding reads the same
        // on every side at every window shape.
        VStack(alignment: .leading, spacing: 6) {
            PaneMosaic(node: tab.splitRoot, focusedPaneID: tab.focusedPaneID)
                .frame(width: Self.previewSize.width, height: Self.previewSize.height)
                // The gaps between leaves are the miniature split dividers, so
                // they need a color of their own. Left transparent they showed
                // whatever sat behind the card — the selection fill on the
                // selected one, the glass panel on the rest — which made two
                // cards of the same layout read as different things.
                .background(MactermTheme.border)
                .clipShape(RoundedRectangle(cornerRadius: Self.previewCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Self.previewCornerRadius, style: .continuous)
                        .strokeBorder(MactermTheme.border.opacity(0.6), lineWidth: 1)
                )
                // The preview floats a little over the card — and over the
                // selection fill behind it — so a card reads as stacked
                // content rather than printed flat on the panel.
                .shadow(color: .black.opacity(0.24), radius: 5, x: 0, y: 2)

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
            .frame(width: Self.previewSize.width, alignment: .leading)
        }
        .padding(Self.cardPadding)
        // The selection fills the WHOLE card — preview and title row together,
        // in `surface` — rather than a halo hugging the preview: with the
        // icon, title and picture all inside one surface, the selected card
        // reads as a single chosen thing rather than a highlighted picture
        // with an unhighlighted caption.
        .background(
            RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                .fill(isSelected ? MactermTheme.surface : .clear)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// One spoken label for the whole card: number, title, execution state,
    /// working directory and pane count, so VoiceOver users get everything
    /// the picture shows.
    private var accessibilityLabel: String {
        [
            "Tab \(number)",
            tab.sidebarTitle,
            statusText,
            workingDirectoryText,
            paneCount > 1 ? "\(paneCount) panes" : nil,
        ]
        .compactMap(\.self)
        .joined(separator: ", ")
    }

    private var statusText: String? {
        switch tab.executionState {
        case .idle: nil
        case .running: "Running"
        case .done: "Completed"
        }
    }

    private var workingDirectoryText: String? {
        guard let pane = tab.focusedPane else { return nil }
        let path = pane.isRemote
            ? pane.projectPath
            : (pane.nsView?.currentPwd ?? pane.projectPath)
        guard !path.isEmpty else { return nil }
        return pane.isRemote ? path : (path as NSString).abbreviatingWithTildeInPath
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
                } else if let preview, !preview.lines.isEmpty {
                    PanePreviewText(lines: preview.lines, columns: preview.columns)
                }
            }
            .clipped()
            // The focused pane is marked the way the split view marks it: the
            // others are dimmed rather than this one being highlighted.
            .overlay(isFocused ? Color.clear : Color.black.opacity(0.22))
    }
}

/// Fallback preview for a pane no frame was ever captured from — a tab that
/// has never been focused this run (see `PanePreview`).
///
/// Typeset to stand in for the picture we couldn't take: the pane's own column
/// count is mapped onto the card's width, so a line lands at the same relative
/// size a real thumbnail of that pane would have shown, and rows run top down
/// like the screen they came from. A fixed point size was the earlier cut and
/// it read as a bug — 5pt text in a 100pt card made an idle shell's prompt
/// span the whole width, several times larger than the same prompt in the
/// captured frame beside it, and bottom-aligning it put a fresh shell's prompt
/// under the card instead of at its top.
private struct PanePreviewText: View {
    let lines: [String]
    /// The terminal's width in columns. nil falls back to a typical 80.
    let columns: Int?

    /// Advance width of a monospaced glyph as a fraction of point size. SF
    /// Mono and friends sit at 0.6; close enough to place the text at the
    /// right scale, which is all this needs to do.
    private static let advanceRatio: CGFloat = 0.6
    /// Point size the text is typeset at before being scaled down to fit. The
    /// fitting is a TRANSFORM, not a smaller font: a card leaf can be under
    /// 50pt wide (a quadrant of a 2x2 split), which works out to well under a
    /// point per glyph, and asking for a font that small either renders
    /// nothing or renders wrong. Scaling a comfortably-typeset block keeps the
    /// geometry exact at any size and can never drop the content — an earlier
    /// cut computed a font size directly and skipped the text below a 1.6pt
    /// floor, which left every never-focused SPLIT tab's card blank while
    /// single-pane cards squeaked over the line at 1.62pt.
    private static let referenceSize: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let width = CGFloat(max(columns ?? 80, 1)) * Self.referenceSize * Self.advanceRatio
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: Self.referenceSize, design: .monospaced))
                        .foregroundStyle(MactermTheme.fgMuted)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .frame(width: width, alignment: .topLeading)
            .scaleEffect(geo.size.width / width, anchor: .topLeading)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .clipped()
    }
}
