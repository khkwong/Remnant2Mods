# InventoryTracker — mod reference

Status: **Lua MVP feature-complete and released** as of 2026-07-30 (data pipeline finished 2026-07-28, UI shipped 2026-07-28, clickable-link investigation closed 2026-07-30). Source: `InventoryTracker/Scripts/main.lua` + `InventoryTracker/Scripts/master_list_data.lua` (generated, not hand-maintained). This doc is the what/why of this mod specifically; engine/UE4SS techniques and the discovery trail live in `docs/remnant2-modding-research.md` (§3.10–3.18). Maintenance playbook: `dev-docs/INVENTORY_TRACKER_DONE.md`. A separate, much larger full-vision version of this mod (real clickable tabs and links, built as a Blueprint asset instead of pure Lua) is tracked as a future project in `TODO.md` — not started, not required for this release.

## What it does

Shows which unique equippable items the player currently has vs. what's missing, across 8 categories: Rings, Amulets, Armor, Weapons, Weapon Mods, Mutators, Engrams, and Unlockable Traits — 699 tracked entries total. Press **F8** in-game to open a full-screen panel; **Page Up**/**Page Down** cycle through the categories. Consumables and Archetype/Core traits are deliberately out of scope (see Known limitations below).

## User guide

### Opening the panel

- **F8** toggles the panel open/closed. It covers the full screen, with a scrollable list of the current category's items.
- **Page Up** / **Page Down** cycle to the previous/next category while the panel is open. The header line shows the current category name, its position (e.g. "3/8"), and an owned/total count (e.g. "214/328").
- The mouse cursor becomes visible and the scroll wheel scrolls the list while the panel is open; character movement via keyboard still works underneath it (the panel doesn't pause the game).
- Ownership is rescanned fresh from the live game state every time the panel is opened — nothing is cached across opens/closes, so switching characters or picking something up is always reflected accurately on the next F8.

### Reading a row

- **`[X]`** (green name) — owned. **`[ ]`** (red name) — missing.
- Each row also shows a plain-text wiki link (`remnant2.wiki.gg/wiki/<ItemName>`) — **not clickable** (see Known limitations), but readable/copyable if you want to look the item up.
- **Traits** display differently from every other category: a found trait shows its allocated level (e.g. `7/10`) instead of just `[X]`; a missing trait shows the wiki's "where to find it" text next to the link instead of just `[ ]`.

## Key implementation facts

- **No persistent "ever obtained" flag exists anywhere in the game's native reflection** (confirmed by grepping the full UE4SS CXX header dump for `Discover`/`Journal`/`Codex`/`Compendium` — zero matches). This mod can only ever reflect *current* inventory contents — a sold or dismantled unique will show as missing again even if you found it before. This is a permanent, structural ceiling, not a bug.
- **Ownership check** (rings/amulets/armor/weapons/mods/mutators/engrams): scan the player's `RemnantPlayerInventoryComponent.Items` array (a plain property read, no function calls) and match each entry's item class against the master list by class path. Deliberately does **not** call `HasItem()` — that function takes a `TSoftClassPtr` (a struct, not a raw pointer) and crashed the game when called with a raw class value.
- **Ownership check for Traits is different**: read `UTraitsComponent.Traits` (a `TArray<FTraitInfo>` on the player pawn) — presence in that array means the trait is unlocked, and its `Level` (0–10) is real allocated points. Absence is genuinely different from a level of 0.
- **Master list build pipeline**: a Python pipeline (`scripts/InventoryTracker/`, tracked in git) queries `remnant2.wiki.gg`'s Cargo API for most categories (clean, structured data — name + full class path per item) and falls back to FModel-export scanning + wiki cross-referencing for the two categories without API coverage (Weapon Mods, due to bad data spot-checked twice; Traits, which have no API table at all). Output is compiled into `master_list_data.lua`, a generated data file `main.lua` loads via `require` — never hand-edited directly.
- **The in-game UI is built entirely from bare Lua-constructed UMG widgets** (`StaticConstructObject` on native `/Script/UMG.*` classes) — no existing Blueprint template asset was needed. Full construction recipe: research doc §3.17.

## Known limitations / deliberate scope cuts

- **Consumables are out of scope.** They're mostly purchased/stackable rather than the kind of "might need to re-roll a dungeon for this" item this mod exists to track (user decision, 2026-07-28).
- **Core and Archetype traits are out of scope.** Core traits are always owned (nothing to track); Archetype traits' `Level` in `UTraitsComponent.Traits` mirrors the archetype's own level, not player choice, and every archetype appears in that array regardless of whether the player owns the corresponding Engram — unusable for ownership tracking. Engram ownership (a real, trackable thing) is covered separately via the standard inventory scan.
- **4 items are excluded** for having no wiki match at all (`BlessedNecklace`, `Bloodtrail`, `MoltenShot`, `NoxiousBolt`, `FlickerCloak`) — `FlickerCloak` and `BlessedNecklace` are confirmed leftovers from the original *Remnant: From the Ashes*; the other two are unconfirmed either way.
- **Wiki links are plain text, not clickable.** UE4SS Lua cannot bind `Button.OnClicked` (a `MulticastInlineDelegateProperty` — unsupported by UE4SS's Lua reflection bridge), and a separate investigation into detecting clicks via `RegisterHook` on `UserWidget:OnMouseButtonDown` also came up empty (registered without error but never fired, across every target type tried — research doc §3.18). Real clickable links need a compiled Blueprint asset instead of pure Lua; tracked as a future project in `TODO.md`, not part of this release.
- **No tabs** — category switching is Page Up/Page Down instead of clickable tabs, for the same reason as above.
- **Ownership is current-inventory-only**, per the structural ceiling above — this mod cannot show "items you've ever found."
