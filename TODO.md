# TODO / open questions

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
