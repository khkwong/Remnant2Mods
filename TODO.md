# TODO / open questions

## InventoryTracker: full UI vision deferred to Blueprint modding

**Status 2026-07-28: deferred, not abandoned.** User's original ask for the InventoryTracker UI: a spreadsheet-style popup, a tab per category, two columns per row (item name — colored green if owned, red if missing; a clickable link to that item's wiki page). Explicitly set aside until the user is ready to invest time in learning Blueprint/UE project work — pick this back up then, don't rediscover the ask from scratch.

**Why it's deferred**: the blocker is clickability, not the visuals. UE4SS Lua cannot bind `MulticastInlineDelegateProperty` at all — confirmed twice (`MoreLoadoutSlots`' extra loadout tiles, research doc §3.4o; reconfirmed here since a from-scratch Lua-built `Button` has no existing Blueprint click-handler function to hook-forward from, unlike that earlier case which at least had one to work around with). That rules out real clickable tab buttons and clickable wiki-link hyperlinks in pure Lua. Everything else — colored text, scrolling, a background, nested layout — **is** achievable in pure Lua and was proven live (research doc §3.17 has the full technical recipe). Current plan: ship a Lua-only MVP first (one scrollable list instead of tabs, plain-text wiki-link column instead of clickable), and build the full vision as a Blueprint-modding project later.

**MVP construction fully proven, 2026-07-28** (research doc §3.17, points 6-8): a bounded, colored, scrollable panel — `Overlay → SizeBox(900×500) → Border → ScrollBox → VerticalBox → rows` (each row a `HorizontalBox` with a colored name `TextBlock` + plain-text URL `TextBlock`), positioned top-left, mouse-wheel scrolling working, character still controllable while it's open (`SetInputMode_GameAndUIEx`) — all confirmed live in-game with 30 test rows. No remaining unknowns for this shape; next step is wiring it up to `InventoryTracker`'s real `MASTER_LIST` + ownership data instead of test rows, plus keybind-driven category switching.

**Lua-only vs. Blueprint modding, for when this gets picked back up:**

| | Lua-only (current MVP) | Blueprint modding |
|---|---|---|
| Clickable tabs/buttons | ❌ blocked (delegate limitation) | ✅ compiled delegates work normally |
| Clickable wiki hyperlinks | ❌ blocked, or unproven `RichTextBlock` decorator/`LaunchURL` territory | ✅ straightforward |
| Colored rows, scrolling, background | ✅ proven (research doc §3.17) | ✅ (and easier — visual designer instead of blind struct write-back from Lua) |
| Iteration speed | Hot-reload, seconds per change | Cook + package a `.pak`, full rebuild per change |
| New tooling needed | None — same as every mod so far | A real UE 5.2 project (`Rem2Proj`-style setup, research doc §4.2 step 8 — flagged early, never actually used in this project) |
| Data bridging | Direct — Lua reads `TraitsComponent`/inventory and writes straight into the widgets it built | Lua would still own all the data-reading (native game state isn't reachable from a static Blueprint asset), then instantiate the custom Blueprint widget via `WidgetBlueprintLibrary.Create` — the *same* proven call already used for `Widget_Loadout_C` — and feed it data through exposed properties/functions |

Nothing built for the Lua MVP is wasted if/when the Blueprint version happens — the data-reading Lua side (ownership scans, `TraitsComponent` reads) carries over unchanged either way; only the widget-construction half would be replaced.

## Was the T/I/M tab-hotkey suppression ever actually needed?

**RESOLVED 2026-07-14 (EquipmentSearch): yes, keep it.** The equipment-screen
search box was definitely focused — every keystroke landed in the box and fired
its `TextChanged` event — and typing **M** still navigated to the map. So a
focused `EditableTextBox` receiving characters does NOT stop the menu's hotkey
dispatch; the "focused box consumes letters by itself" hypothesis below is
falsified, and LoadoutNamer's suppression stays. (Why U/J/O/P/B seemed inert
during LoadoutNamer edits remains unexplained — possibly context-gated on that
screen — but it no longer matters: the suppression is demonstrably load-bearing.)
EquipmentSearch now suppresses the same three tabs while its box has focus,
using the filter widget's `OnAddedToFocusPath`/`OnRemovedFromFocusPath`
overrides as the session boundary (research doc §3.6c).

Original status as of 2026-07-13 (LoadoutNamer, tab-hotkey work):

- Full in-game-menu letter-hotkey map (user-tested, keyboard): **T** Traits, **I** Inventory, **M** Map, **U** Fragments, **J** Character, **O** System, **P** Archetype, **B** closes the menu entirely, **Q/E** scroll tabs. Dispatch for T/I/M confirmed as `Widget_InGameMenu_C:FocusTraits/FocusInventory/FocusMap` (research doc §3.4aa); the others presumably have sibling `Focus*` functions.
- LoadoutNamer currently suppresses only T/I/M during a rename by hiding those three tab buttons (`SetVisibility(2)`; the game's `Focus*` functions early-out on the tab's `IsVisible()`).
- **The open question**: with the suppression in place, U/J/O/P/B *also* don't navigate while typing in the rename box — even though nothing suppresses them. That suggests a properly-focused `EditableTextBox` may consume letter keys on its own, and the original "T/I/M navigate while typing" repro may actually have been typing into a **defocused** box (accidental click-out). If so, the visibility suppression is redundant and the real hazard is focus loss, not hotkeys.
- **To resolve** (cheap test next time we're in this code): comment out `suppressTabHotkeys()` in `beginRename`, reload, and type t/i/m into a freshly-opened, definitely-focused rename box. If nothing navigates, drop the suppression (or keep it as cheap insurance and note why). Also worth checking what happens on **B** and **Q/E** with a *defocused* box mid-edit — B closing the menu mid-edit exercises the stale-cleanup path.

## Carried-over LoadoutNamer polish

Both former polish items shipped 2026-07-13 (tooltip "F2 Rename" prompt via `ExtraActionList` + `Widget_KeyIcon`; edit-box styling via WidgetStyle write-back — see research doc §3.4bb and `docs/loadout_namer.md`). Remaining nice-to-haves, all optional:

- Per-character/save names (currently one shared name map per install).
- Verify the rename flow in a co-op session (no known hazard, just untested).
