# Tab Switcher: Ours vs Upstream — Backport Notes

Context: `feat/horizontal-tabs` previously carried its own Recent Tab switcher
(`0ceffbe`..`f6742c1`). `upstream/main` landed its own (#344/#346 previews,
#347 padding/default-on). The merge of `ead9c4f` **keeps upstream's
implementation and deletes ours**, then backports the pieces of ours worth
keeping. Branch-local — not meant for upstream PRs.

## Status

### Applied on top of the merge

- **Standalone floating panel** (Arc-style): the strip lives in its own
  borderless non-activating `NSPanel` centered on the terminal window
  (`TabSwitcherPanelPresenter`), NOT in an in-window overlay — so a strip
  wider than the window extends past the window's edges (clamped only by the
  screen). The panel never becomes key: the terminal keeps keyboard focus, so
  modifier-release commit and Escape keep flowing through the app's normal
  key routing. Upstream's in-window strip is clipped to the window.
- **Panel chrome is bare glass + the WINDOW shadow**: `glassPanelBackground`
  (liquid glass / material, no stroke — `glassPanel()`'s hairline border read
  as a dark ring wrapped around glass that draws its own edge) plus
  `panel.hasShadow = true`, deliberately NOT ArrowlessPopoverPanel's
  macOS 26 `hasShadow = false`: that popover is anchored to the tab bar where
  proximity already reads as elevation, while this strip floats mid-window
  and read pasted-on without a shadow. The shadow is the window-server's,
  never a SwiftUI `.shadow` — the window is exactly content-sized, so a view
  shadow clips at the window bounds (a straight cut through the band), and
  enlarging the window for it would leave a dead transparent frame
  swallowing clicks. The window shadow draws outside the window, following
  the glass's rounded shape. Hence `GlassPanel.swift` is exactly upstream's —
  our `GlassPanelShadow.theme` parameterization was dead code and is deleted.
- **Sizing**: width computed from constants
  (`TabSwitcherStrip.width(for:)`), height MEASURED after a layout pass with
  that width proposed (`layoutSubtreeIfNeeded` → `fittingSize.height`, the
  `ArrowlessPopoverPresenter` pattern). Measuring without a width proposal
  returns near-zero for glass-backed content — that was the invisible-panel
  first-press bug. A hand-computed height constant was tried and was wrong;
  don't go back.
- **Selection**: our full-card `surface` fill (preview + title row as one
  surface) instead of upstream's preview-hugging halo, plus our per-preview
  shadow (black 0.24 / r5 / y2).
- **Fixed card metrics**: card width 160, preview 16:10 (≈146×91.25) at every
  window/pane aspect, replacing upstream's pane-container-aspect shaping
  (`paneContainerAspect` / `PanePreviewCapture.containerAspect` deleted).
  `PaneMosaic`'s ratio-driven layout survives; captured frames letterbox
  `.fit` in their leaves.
- **No viewport, no slivers, no scrolling**: the panel's width is the
  content's width. Upstream's fixed-capacity viewport + peek slivers +
  translated row were removed with the standalone panel — overflow past the
  window replaces sliding inside it. Candidate count is bounded by
  preference instead.
- **Candidates capped by preference**: `recentTabCandidates` (Settings →
  Appearance → Tab Switching, stepper 2…12, **default 5**) bounds the strip;
  direct cycling keeps the full recency order. Upstream walked the full order.
- **Escape cancels** the in-flight cycle (responder branch); direct mode
  restores the original tab via `peekTab` (MRU untouched).
- **Click outside the panel cancels** — a local `NSEvent` monitor while the
  panel is up (cancels and swallows app-delivered presses outside the panel;
  other apps' windows never reach it). Upstream let presses fall through to
  the terminal.
- **Project switch cancels** the cycle (`activeProjectID` didSet) — the
  modifier release can no longer commit a foreign tab id against the new
  workspace.
- **Accessibility**: per-card labels (number, title, execution state, working
  directory, pane count) + `.isSelected` traits, backported from our card.
- Title row deliberately NOT backported — upstream's `TabGlyph` +
  `sidebarRowTitle` stays (ours carried cwd and a trailing index digit).

**Trap worth remembering**: the strip renders in a fresh `NSHostingView`,
which is a NEW SwiftUI root — environment values do not travel with a view
VALUE. The call site must re-inject `.environment(appState)` (as
`HorizontalTabBar` does for its `ArrowlessPopoverPresenter` content); without
it `PaneMosaicLeaf`'s `@Environment(AppState.self)` fatals on first layout
and the app crashes the moment the strip appears.

**Second trap**: never put `.transient` in the panel's
`collectionBehavior`. It vanishes the window the moment the app deactivates —
which can happen mid-gesture — and the strip blinks out from under a still
held modifier. The overlay's own dismissal paths (modifier release, Escape,
outside click, project switch) already own its lifetime.

### Still open (not requested)

- **Menu/palette invocation strands the strip** — upstream's `action(in:)`
  only cycles; a pointer invocation has no modifier release to commit, so
  the strip stays up until some later modifier blip commits whatever is
  highlighted. Our old `performMenuAction` distinguished keyboard vs pointer
  invocation and committed immediately — the fix to port if this ever
  bothers anyone upstream too.

## Underlying differences that remain (context)

- **Preview pipeline**: upstream's rolling `panePreviews` cache (foreground
  poll, 0.75s throttle, synchronous sweep at cycle start, real viewport-text
  fallback) — strictly better than our lazy capture + fake placeholder art.
- **Preference migration**: anyone who opted out on our branch
  (`showRecentTabSwitcher = false`) lands on the new default ON. Honor the
  old key as an implicit opt-out if this ever ships.

## Automation seam — deleted

The merge's first pass kept our e2e automation adapted (see git history);
dropped in favor of unit coverage in `AppStateTests` (cycle/commit/cancel,
candidate cap, project-switch cancel, escape restore) — upstream carries no
such seam.
