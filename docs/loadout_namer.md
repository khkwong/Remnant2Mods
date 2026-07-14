# LoadoutNamer — mod reference

Status: **feature-complete and user-confirmed** as of 2026-07-13. Source: `LoadoutNamer/Scripts/main.lua`. This doc is the what/why of this mod specifically; engine/UE4SS techniques live in `docs/remnant2-modding-research.md` (§3.4y, 3.4z, 3.4aa, 3.4bb).

## What it does

- **Rename**: hover a loadout tile on the character screen, press **F2** → an `EditableTextBox` styled to the game's look (GFGRemnantCracked font 10, ashen 0.85 text, dark translucent fill) replaces the title text in the tile's title row. **Enter/F2** commits, **Escape** cancels, committing empty removes the custom name.
- **Display**: names render via `tile.LabelOverride` + `Refresh()`, re-applied whenever the panel is constructed (waits for MoreLoadoutSlots' 20 tiles). Tile shows at most 18 chars (`..`-truncated); the hover tooltip's title (`ItemLabel`) shows the full name (cap 32).
- **Tooltip integration**: title swap per hover, plus an "F2 Rename" prompt injected into the tooltip's `ExtraActionList` action row (hidden on the Last Gear State tile).
- **Persistence**: `ue4ss/Mods/LoadoutNamer/loadout_names.txt`, tab-separated `recordIndex<TAB>name` lines, whole-file rewrite on every commit. Tabs/newlines stripped from names on commit.
- **Tab-hotkey suppression**: during an edit, the Traits/Inventory/Map tab buttons are set Hidden (visibility 2, keeps layout space) so T/I/M can't yank the menu; restored on every exit path. Confirmed necessary 2026-07-14: EquipmentSearch proved a focused, character-receiving text box does NOT block the hotkey dispatch (TODO.md, research doc §3.6c).

## Key implementation facts

- Record indices: vanilla 0–7, mod tiles 8, 9, 11–20; **record 10 is the reserved Last Gear State auto-save** — F2 refuses it and the tooltip prompt hides on it.
- Default labels: records ≤ 10 regenerate natively from an empty override; records > 10 must get back MoreLoadoutSlots' pinned `"Loadout N"` (N = record index) when a custom name is removed.
- Hover identity comes from the `Widget_Loadout_C` OnMouseEnter bound-event hook (`..._4_OnAdvButtonClickedEvent...`); the hook body only does `self:get()` + an `Index` property read.
- The rename box lives in the title row (`tile.Label:GetParent()`); the label is blanked and its width reservation released via `SetMinDesiredWidth(0)` for the edit, restored to 130 after (real setter mandatory — H4).
- Tooltip work runs on a ~1s 50ms poll per hover (`FindAllOf("Widget_LoadoutTooltip_C")`, skip `Default__`), superseded by a generation counter on the next hover. Prompt widgets are tracked per tooltip instance (`ExtraActionList` full name).
- Names file path is probed from two candidates at load because the game's io CWD is the exe dir; the `ue4ss/Mods/...` prefix is the one that resolves on the current install.

## Known warts / deliberate scope cuts

- U/J/O/P/B menu hotkeys are unsuppressed and appear harmless while typing (unexplained, given T/I/M demonstrably needed suppression — see TODO.md).
- Edit box is still an engine `EditableTextBox` with tinted default brushes — close to native, not pixel-identical (no cracked border art).
- Names are per-install, not per-character/save: all characters share the record-index → name map.
- Multiplayer: rename flow untested in co-op sessions (tooltip/panel paths follow the GetOwningPlayer rule, so no known hazard — just unverified).
