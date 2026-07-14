# EquipmentSearch — mod reference

Status: **feature-complete and user-confirmed** as of 2026-07-14. Source: `EquipmentSearch/Scripts/main.lua`. This doc is the what/why of this mod specifically; engine/UE4SS techniques and the discovery trail live in `docs/remnant2-modding-research.md` (§3.6, 3.6a, 3.6b, 3.6c). Maintenance playbook: `dev-docs/EQUIPMENT_SEARCH_DONE.md`.

## What it does

- **Search bar**: the game's own shipped-but-hidden search bar (`Widget_InventorySearchFilter` inside every `Widget_InventoryList_C`) is made permanently visible on all inventory item grids — rings, amulets, armor, relics, weapons, plus the Inventory tab's materials/quest/usable lists. Its vestigial category dropdown (leftover dev-test options) is collapsed; the W-filters menu already covers category filtering.
- **Filtering**: live per keystroke, substring match against item **name AND gameplay-effect text** ("grey health" finds every ring whose effect mentions grey health). Lore — the `Description` paragraph and `FlavorText` quote — is deliberately excluded: search is gameplay-only. Non-matching cards collapse so matches flow together; the X button (or emptying the box) restores the full grid.
- **Tab-hotkey suppression**: while the search box has keyboard focus, the menu's Traits/Inventory/Map tab buttons are set Hidden (visibility 2, keeps layout space) so typing t/i/m can't yank the menu to another tab; restored when focus leaves. Engages on click-in, before the first keystroke.
- **Debug commands** (typed into the search box; kept in the shipped mod): `!<word>` prints the full cached text of every matching item, `!!` clears the text cache, `!?` lists items whose cache is name-only — the after-a-game-patch health check (0 of 213 rings as of 2026-07-14).

## Key implementation facts

- **The vanilla filter pipeline is dead, so matching and hiding are both ours.** The shipped bar was a keyword→tag prototype fed by `DataTable_ItemFilters`, which ships empty; and every vanilla rebuild entry point (including the once-planned `ShouldHideItem` hook) early-outs when the game thinks nothing changed. The mod instead walks `list.InventoryGrid`'s card children on query change and calls `SetVisibility` per card, recording each hidden card's prior visibility for exact restore.
- **Two hiding layers on the bar**: the `CanSeeSearchBar` gate binding on the filter child (fires only during construction, inert after — a plain visibility write sticks) and the text box itself, `Collapsed` at the asset level. Both are unhidden per list construction (`NotifyOnNewObject` + a ~2 s readiness poll), with one delayed re-apply to outlast the construction-time binding evaluations.
- **Search text per ItemID** comes from each card's `Get_InspectInfo({})` (BlueprintPure; UE4SS spreads the out-struct's fields into the passed table), cached for the session, built lazily from each list's own grid children — never the global card pool (stale pooled cards from destroyed screens poisoned the cache once).
- **Effect text lives in two different places by item style**: stat-style items → `Mods[].Label` (`InspectMod`); trigger-style items (~30 rings) → `Stats[].CustomDescription`, inherited from `InspectStatBase`. Field names are resolved at load by reflection, **per array** — Stats and Mods entries are different structs, and reading a field a struct doesn't own is a native crash (hazard H9); the reflection walk must include the `GetSuperStruct()` chain or inherited fields are silently missed (H10).
- **Text normalization**: cached text and queries both get lowercased, rich-text markup stripped (`<stat>`, `<span color=...>`), NBSPs and whitespace runs collapsed — phrase matching fails otherwise ("grey health" with a tag between the words).
- **Multiple lists coexist** (equipment screen + three Inventory-tab lists); each is tracked by full name and synced against its *own* text box — a single "current list" variable let one list's typing stomp another's filter state.
- **Rebuild resilience**: post-hooks on the game's `Update Inventory List` / `Build Inventory List` passes (plus a one-shot 150 ms delayed re-apply — Build repopulates asynchronously) and a 300 ms watchdog that silently re-applies active filters, because some rebuild paths (equip → popup reopen) bypass both hooks. A full re-apply pass measured ~2 ms.
- **Hotkey suppression mechanism**: tab switches early-out when the tab *button* isn't visible (LoadoutNamer's probe, §3.4aa). The typing-session boundary is the filter widget's `OnAddedToFocusPath` / `OnRemovedFromFocusPath` overrides — they fire when keyboard focus enters/leaves the box. Only tabs that were actually visible get hidden, and only those get restored; a leaked Hidden state self-heals when the menu reopens.
- Hooks on `/Game/` classes can't register at mod start on a fresh launch (Blueprint not loaded yet) — registration is deferred to the first list capture.

## Known warts / deliberate scope cuts

- Upgraded items keep their old "+N" level suffix in cached text until relaunch (session-lifetime cache by design; the name and effect words still match).
- The Inventory tab's lists don't persist the filter across tab switches (each switch rebuilds; retyping is cheap).
- The search covers item grids only — trait/archetype screens use different widgets and are out of scope.
- Cache assumes effect text is static per ItemID within a session; items whose display text changes with game state would show stale matches until `!!`.
