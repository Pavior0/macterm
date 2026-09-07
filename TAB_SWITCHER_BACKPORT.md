# Tab Switcher: Ours vs Upstream — Backport Notes

Context: `feat/horizontal-tabs` previously carried its own Recent Tab switcher
(`0ceffbe`..`f6742c1`). `upstream/main` landed its own (#344/#346 previews,
#347 padding/default-on). The merge of `ead9c4f` **keeps upstream's
implementation and deletes ours**. This file records the differences for the
backport work that follows. Branch-local — not meant for upstream PRs.
A visual diff lives in `show-me-tab-switcher-ui-diff.html` (temp dir; reopen
by re-running the show-me step).

## What was deleted (ours)

- `Macterm/Views/RecentTabSwitcher.swift`, `RecentTabPreviewStore.swift`,
  `Macterm/App/RecentTabCycle.swift`
- Preference `showRecentTabSwitcher` (key `macterm.tabs.showRecentTabSwitcher`,
  default **off**) — replaced by upstream's `showTabSwitcherOverlay`
  (key `macterm.tabSwitcher.overlay`, default **on**).
- Benchmark integration: `recentTabPreviewMetrics` status fields and
  `benchmark.py`'s `switcher-preview` state (reverted to upstream's
  `benchmark.py`). Upstream's preview pipeline is synchronous-from-cache, so
  "preview fill time" no longer exists as a metric.
- Escape-to-cancel, background-tap-to-cancel, menu-invocation commit — see
  behavioral diffs below.

## What was kept (upstream)

- `TabSwitcherOverlay.swift`, `TabIcon.swift`, `GlassPanel.swift`,
  `Terminal/PanePreview.swift`; the `tabCycleOrder`/`tabCycleIndex` state
  machine; rebindable modifier-release commit
  (`recentTabHoldModifiers` in the flags handler); preference default ON.

## UI differences (the "UI 侧有点区别" list)

1. **Preview pipeline.** Ours captured lazily when the switcher opened
   (async, progressive, CIContext / Display P3, fake placeholder art when a
   pane had no frame). Upstream maintains a rolling `panePreviews` cache fed
   by the 250 ms foreground poll (0.75 s throttle) plus a synchronous sweep at
   cycle start; the no-frame fallback is the pane's **real viewport text**
   typeset to scale — no fake prompt lines.
2. **Strip mechanics.** Ours was a real `ScrollView` (LazyHStack, visible
   indicators, `scrollTo(.center)` auto-scroll with hover suppression so
   manual scrolling never fights it). Upstream is a fixed-capacity **viewport**
   computed from window width, with the whole row translated under `.clipped()`,
   eased 0.16 s offset, and "peek" slivers at the panel edges as the overflow
   indicator. Upstream cards are shaped by the live pane-container aspect
   ratio; ours were fixed 202×154.
3. **Card title row.** Ours: `horizontalTabTitle(projectDirectory:)` (includes
   cwd) + trailing index digit. Upstream: `sidebarRowTitle` + `TabGlyph` —
   the single glyph decision shared with the sidebar, honoring all four icon
   preferences including the new project-color-tag tint. Upstream's numbered
   icon variants consume the tab's 1-based workspace number.
4. **Selection chrome.** Ours filled the whole card; upstream draws a halo
   hugging the preview, concentric with its corner — uniform padding by
   construction (#347).
5. **Panel chrome.** Ours rolled its own glass/material background + border +
   shadow + 5 %-height upward offset. Upstream reuses the command palette's
   `glassPanel()`.
6. **MRU membership.** Ours capped the strip at 5 most-recent tabs; upstream
   walks the full recency order (the viewport keeps the panel width stable).
7. **Accessibility.** Ours had explicit per-card accessibility labels and
   `.isSelected` traits; upstream has none specific.

## Behavioral diffs — backport candidates

Ordered by value:

1. **Menu/palette invocation leaves the strip stranded (upstream bug-ish).**
   Ours distinguished keyboard vs pointer invocation (`performMenuAction`):
   a pointer invocation has no modifier release, so it committed immediately.
   Upstream's one-shot `action(in:)` only cycles — invoking "Recent Tab" from
   the menu/palette opens the strip with nothing to commit it (any later
   modifier blip commits whatever is highlighted). **Backport: commit (or
   one-shot cycle+commit) on non-keyboard invocation.**
2. **Escape-to-cancel.** Ours cancelled the in-flight cycle on Escape
   (responder branch + unit/e2e tests). Upstream has no Escape path; the only
   exits are commit and click. **Backport: cheap, well-tested in our history.**
3. **Background tap-to-cancel.** Ours had a full-overlay tap layer calling
   cancel; upstream lets presses outside the panel fall through to the
   terminal (deliberate: the gesture is over in under a second). Judgment
   call; ours was friendlier for pointer users.
4. **Project switch mid-cycle.** Ours cancelled the cycle when
   `activeProjectID` changed (didSet guard + test). Upstream leaves the
   in-flight order pointing at the old workspace; the eventual release
   commits against the *new* project's workspace with a foreign tab id
   (select no-ops). Rare (requires switching project while holding the
   binding), but the guard is three lines.
5. **Accessibility labels** — no-brainer to re-add on upstream's cards.

## Automation seam — deleted (second pass)

The first merge commit kept our e2e automation adapted to upstream's state
machine (`cycleRecentTabForAutomation` forcing the overlay path via
`isTabSwitcherOverlayEffective`, status fields `recentTabSwitcherVisible` /
`recentTabSelectedTabID` re-derived from `tabCycleTabIDs` /
`tabCycleSelection`). Dropped on review: upstream has no such seam, and the
switcher state machine is already covered by unit tests
(`recent_tab_cycle_defers_selection_and_commits_mru` etc. in
`AppStateTests`). Removed with it: `e2e/test_recent_tab_switcher.py`,
the `recent-tab-cycle` / `recent-tab-commit` Darwin notifications, and the
status fields (back to upstream's `ControlStatusInfo` shape exactly).

## Preference migration note

Anyone who opted **out** on our branch (`showRecentTabSwitcher = false`) has
no equivalent setting after this merge — the new key defaults to ON. Harmless
for a feature branch, but if this ever ships, honor the old key as an
implicit opt-out in `Preferences.init`.
