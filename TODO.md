# TODO / open questions

## Was the T/I/M tab-hotkey suppression ever actually needed?

Status as of 2026-07-13 (LoadoutNamer, tab-hotkey work):

- Full in-game-menu letter-hotkey map (user-tested, keyboard): **T** Traits, **I** Inventory, **M** Map, **U** Fragments, **J** Character, **O** System, **P** Archetype, **B** closes the menu entirely, **Q/E** scroll tabs. Dispatch for T/I/M confirmed as `Widget_InGameMenu_C:FocusTraits/FocusInventory/FocusMap` (research doc §3.4aa); the others presumably have sibling `Focus*` functions.
- LoadoutNamer currently suppresses only T/I/M during a rename by hiding those three tab buttons (`SetVisibility(2)`; the game's `Focus*` functions early-out on the tab's `IsVisible()`).
- **The open question**: with the suppression in place, U/J/O/P/B *also* don't navigate while typing in the rename box — even though nothing suppresses them. That suggests a properly-focused `EditableTextBox` may consume letter keys on its own, and the original "T/I/M navigate while typing" repro may actually have been typing into a **defocused** box (accidental click-out). If so, the visibility suppression is redundant and the real hazard is focus loss, not hotkeys.
- **To resolve** (cheap test next time we're in this code): comment out `suppressTabHotkeys()` in `beginRename`, reload, and type t/i/m into a freshly-opened, definitely-focused rename box. If nothing navigates, drop the suppression (or keep it as cheap insurance and note why). Also worth checking what happens on **B** and **Q/E** with a *defocused* box mid-edit — B closing the menu mid-edit exercises the stale-cleanup path.

## Carried-over LoadoutNamer polish (ranked easiest → hardest)

- Tooltip "Rename" prompt in the action-button footer: the footer is NOT in `Widget_LoadoutTooltip` (parent = native `FocusTooltipWidget`, `/Script/GunfireRuntime`) — the owning widget is unidentified; needs FModel/Live View research first.
- Style the rename `EditableTextBox` toward the game's look: `WidgetStyle` struct writes = top of the risk ladder, probe-first, one field per reload.
