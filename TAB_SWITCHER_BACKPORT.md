# Tab Switcher: Ours vs Upstream — Backport Notes

Context: `feat/horizontal-tabs` previously carried its own Recent Tab switcher
(`0ceffbe`..`f6742c1`). `upstream/main` landed its own (#344/#346 previews,
#347 padding/default-on). The merge of `ead9c4f` **keeps upstream's
implementation and deletes ours**, then backports the pieces of ours worth
keeping. Branch-local — not meant for upstream PRs.

## Status

### Applied on top of the merge

- **Panel chrome**: upstream's `glassPanel()` kept, with our shadow
  (`GlassPanelShadow.theme` — theme-colored r24/y10 vs the palette's black
  r20/y8; parameterized so the palette is untouched). Panel insets are ours
  (8, not 14) with the card's own padding carrying the rest.
- **Selection**: our full-card `surface` fill (preview + title row as one
  surface) instead of upstream's preview-hugging halo, plus our per-preview
  shadow (black 0.24 / r5 / y2).
- **Fixed card metrics**: 202×(112+title) at every window/pane aspect,
  replacing upstream's pane-container-aspect shaping
  (`paneContainerAspect` / `PanePreviewCapture.containerAspect` deleted).
  `PaneMosaic`'s ratio-driven layout survives; captured frames letterbox
  `.fit` in their leaves.
- **Candidates capped by preference**: `recentTabCandidates` (Settings →
  Appearance → Tab Switching, stepper 2…12, **default 5**) bounds the strip;
  direct cycling keeps the full recency order. Upstream walked the full order.
- **Escape cancels** the in-flight cycle (responder branch); direct mode
  restores the original tab via `peekTab` (MRU untouched).
- **Click outside the panel cancels** (near-transparent tap-catch layer in
  the overlay; upstream let presses fall through to the terminal).
- **Project switch cancels** the cycle (`activeProjectID` didSet) — the
  modifier release can no longer commit a foreign tab id against the new
  workspace.
- **Accessibility**: per-card labels (number, title, execution state, working
  directory, pane count) + `.isSelected` traits, backported from our card.
- Title row deliberately NOT backported — upstream's `TabGlyph` +
  `sidebarRowTitle` stays (ours carried cwd and a trailing index digit).

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
- **Strip mechanics**: upstream's fixed-capacity viewport + peek slivers +
  0.16s translated row — better than our ScrollView (and at fixed card
  metrics the capacity math is stable again).
- **Preference migration**: anyone who opted out on our branch
  (`showRecentTabSwitcher = false`) lands on the new default ON. Honor the
  old key as an implicit opt-out if this ever ships.

## Automation seam — deleted

The merge's first pass kept our e2e automation adapted (see git history);
dropped in favor of unit coverage in `AppStateTests` (cycle/commit/cancel,
candidate cap, project-switch cancel, escape restore) — upstream carries no
such seam.
