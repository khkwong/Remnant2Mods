# Remnant 2 — Game Structure Research

Living notes on Remnant 2's internal data structures, discovered via live FModel/UE4SS inspection during modding work. This is separate from `remnant2-modding-research.md` (which tracks toolchain/mod-planning progress) — this doc is purely "what did we learn about how the game itself is built," asset by asset, class by class, as we dig through `.uasset` dumps and live object data. Keep appending as new assets are inspected; don't delete superseded entries, mark them corrected instead.

---

## `/Game/_Core/Loadouts/Gear_Loadout` (LoadoutTemplate asset)

Inspected via FModel's "Save Folder's Packages Properties .JSON" dump.

**What it is**: a `LoadoutTemplate` asset defining the *shape* of a single loadout record — i.e. the fixed set of equipment/trait categories that make up one saved build. It does **not** define how many saved loadout presets a player can have (see correction below).

**Structure**: `Gear_Loadout.Slots` is an array of 20 sub-objects, two types:

- **`LoadoutEquipmentSlot`** entries (17 of them) — one per equipment category, each with `SlotName`/`NameID` identifying the slot and a `Priority` int. Full list found: `LongGun`, `HandGun`, `MeleeWeapon`, `Ring1`, `Ring2`, `Ring3`, `Ring4`, `Amulet`, `Helmet`, `Body`, `Gloves`, `Legs`, `DragonHeart` (NameID `Relic`), `AbilitySlot1`, `AbilitySlot2`, `EngramOne`, `EngramTwo`.
- **`LoadoutTraitSlot`** entries (3 of them) — trait/archetype-related slots: `Archetype1` (SlotIndex 0), `Archetype2` (SlotIndex 1), and a third unnamed one (`SlotIndex: -1`, `Priority: 4`) gated by a `HasItemCondition` requiring `/Game/World_Base/Items/Consumables/OrbOfUndoing/Consumable_OrbOfUndoing` — likely a hidden slot tied to the "Orb of Undoing" trait-reset item, not a normal visible slot.

**Correction — this is the wrong asset for loadout *slot count* investigation**: this asset's `Slots` array is easy to confuse with a different, unrelated `Slots` array on `LoadoutComponent` (a native `/Script/Remnant` class, not a Blueprint asset). `LoadoutComponent.Slots` is what actually caps how many *saved loadout presets* exist (its struct elements carry a `NumRecords` field — confirmed live via Lua at `NumRecords = 11` for the Gear template) — that's a completely different concept from `LoadoutTemplate.Slots` here, which just lists the equipment *categories within one record*. Same property name (`Slots`), different class, different meaning — worth remembering as a trap when browsing FModel dumps, since asset JSON dumps don't disambiguate this at a glance.

**Where to actually look for the slot-count cap** (not yet confirmed as of this writing): `LoadoutComponent` is attached to the player Character Blueprints (`/Game/Characters/Player/Base/Character_Master_Player_Base`, `Character_Master_Player`) as a default subobject (`Loadout_GEN_VARIABLE` in Live View). The `NumRecords` default is most likely set as a component-default override on one of those Blueprints, not inside `Gear_Loadout` itself.

---

## `Character_Master_Player_Base` — `Loadout_GEN_VARIABLE` subobject (dead end, but a useful one)

Checked the exported FModel JSON dump of `/Game/Characters/Player/Base/Character_Master_Player_Base` directly (~756KB, alphabetically sorted by component name). Found the `LoadoutComponent` subobject block:

```json
{
  "Type": "LoadoutComponent",
  "Name": "Loadout_GEN_VARIABLE",
  "Flags": "RF_Public | RF_Transactional | RF_ArchetypeObject | RF_WasLoaded | RF_LoadCompleted",
  "Class": "UScriptClass'LoadoutComponent'",
  "Outer": {
    "ObjectName": "BlueprintGeneratedClass'Character_Master_Player_Base_C'",
    "ObjectPath": "/Game/Characters/Player/Base/Character_Master_Player_Base.15"
  }
}
```

**No `"Properties"` key at all.** Compare to sibling components in the same dump (e.g. `PortalEffectsComponent`, `RemnantPlayerInventoryComponent`) which *do* have a `"Properties"` block listing every value the Blueprint overrides from its parent class. The absence here means **this Blueprint does not override `Slots`/`NumRecords` at all** — it's inheriting the value entirely from the native C++ class defaults of `LoadoutComponent` itself (`/Script/Remnant.LoadoutComponent`'s constructor, compiled into the game's C++ code).

**Conclusion — `NumRecords = 11` is not stored in any Blueprint or data asset we can browse/edit via FModel or UAssetGUI.** It's set in native C++ (presumably in `ULoadoutComponent`'s constructor or a `UPROPERTY` default), which isn't visible or editable through normal asset-editing tools.

**This isn't actually bad news for modding it, though** — since UE4SS Lua can read *and write* arbitrary UProperty values on live UObjects regardless of whether the value originated in C++ or a Blueprint (same `SetPropertyValue` mechanism already confirmed working in the amulet example, `remnant2-modding-research.md` section 3.2). The practical implication: **mod #1 likely doesn't need any Blueprint/asset editing at all** — just a UE4SS Lua hook that finds the player's live `LoadoutComponent` (same `FindAllOf("LoadoutComponent")` pattern already used for read-only inspection) and writes a higher `NumRecords` value into the `Slots` array element at runtime, on every game load. Whether this alone makes the UI actually show more slots still depends on whether `Widget_LoadoutsPanel_C`'s tile list is built dynamically from `NumRecords`/`GetMaxRecordsForTemplate` — still the next open question, now to be tested empirically (patch the value via Lua, see if more tiles appear) rather than reverse-engineered from a Blueprint graph.

### Experiment result: writing `NumRecords` does NOT change the visible slot count

Tested live: patched `NumRecords` from `11` to `20` on the player's live `LoadoutComponent.Slots[1]` via `ZZTestMod` (write confirmed successful via readback), then opened the in-game Character > Loadouts screen. **No change** — still exactly 8 named loadout slots + "Last Gear State" (9 total), matching the pre-patch count exactly.

**Conclusion**: the "UI panel is dynamically built from `NumRecords`" hypothesis is **disproven**. `NumRecords` is confirmed writable at runtime (the mechanism works fine) but the loadout screen's tile list is driven by something else — likely either a hardcoded Blueprint-authored list, or a different property/function than the one we patched (e.g. `GetMaxRecordsForTemplate` may compute its return value independent of the raw `NumRecords` field — unlock-gated, DLC-gated, or otherwise). **Back to needing the `Widget_LoadoutsPanel_C` Blueprint graph** (via FModel) to find the actual source of the "8 slots" count — Live View/Lua property reads can't show Blueprint graph logic, only runtime instance data, so this step can't be skipped.

### Bonus finding, corrected: loadout slot names are NOT user-editable in vanilla — mod #2 is still needed

Screenshot of the live Character > Loadouts screen shows every slot carrying a name (e.g. "Loadout 01 — Dynamic Automator", "Loadout 02 — Lucky Diviner"). Initially guessed this meant naming was already a working vanilla feature. **Confirmed wrong by the user**: there is no in-game rename option, and a web search turns up multiple community posts explicitly requesting this as a missing feature — consistent with the "community wants this" finding already noted in `remnant2-modding-research.md` section 2. So these names are auto-generated by the game (most likely derived from the equipped archetype/trait combo — "Dynamic Automator," "Shadow Assassin" etc. read like archetype-flavor labels, not user text), not stored free-text.

**Still useful**: the `SetDisplayNameForLoadout(Loadout, Index, NewDisplayName)` function and `LoadoutRecord.DisplayName` (TextProperty) confirmed to exist on `LoadoutComponent` (section 3.4 above) are very likely still the right mechanism for mod #2 to use — the API for setting a custom name appears to already exist in the engine, it's just not wired up to any player-facing UI. Mod #2 remains a real, needed project: likely calling `SetDisplayNameForLoadout` from an injected input (console command or small widget), rather than needing to build the naming/storage mechanism from scratch.

### Read test: `GetDisplayNameForLoadout` returns empty for every index (0–9)

Called the read-only `GetDisplayNameForLoadout(Loadout, Index)` (safe — no crash, confirms calling functions on `LoadoutComponent` via Lua reflection works fine when parameters are simple types; the earlier crash was specific to the write/FText-parameter path, not function-calling in general) across the full range of indices 0 through 9, on the character's live `LoadoutComponent`. **Every single index returned an empty string** — not just index 0.

**What this means**: `LoadoutRecord.DisplayName` is confirmed empty for the current save's loadout records, despite the UI showing names like "Loadout 01 — Dynamic Automator" for all 8+1 slots. Two readings, not yet disambiguated:
1. The on-screen names are computed client-side/procedurally from the equipped archetype combo, and `DisplayName` is a genuinely separate, currently-unused override field — the UI might fall back to the auto-generated name whenever `DisplayName` is empty, and only use it when actually set. This would mean the mechanism is real and would work once written to (still untested, since the write attempt crashed — see 3.4b).
2. Or `DisplayName`/this function isn't connected to the visible UI text at all, and it's vestigial/used for something else (a different, not-yet-found display surface).

Only a working `SetDisplayNameForLoadout` call (or directly writing `LoadoutRecord.DisplayName`) will disambiguate these — and that's the path that crashed the game once already (3.4b). Next attempt at the write path should research the correct FText-construction/marshaling convention for UE4SS Lua function calls (rather than passing a raw Lua string blind) before retrying live, since another crash is low-cost but avoidable with better prep.

### Recurring curiosity: exactly 2 live `LoadoutComponent` instances, every session — now confirmed NOT safe to treat identically

Now seen consistently across 4 separate test runs — always exactly 2 `LoadoutComponent` instances under `/Game/Maps/Main.Main:PersistentLevel`, on two different `Character_Master_Player_C` instance IDs, both reporting identical `Slots`/`NumRecords` data on read. Not yet root-caused (possibly a listen-server client/server duality, since singleplayer R2 runs as a local listen server internally; possibly related to AAM's `CheatManagerEnablerMod` constructing a CheatManager around the same time in the log).

**New evidence this matters, not just a curiosity**: see 3.4c below — calling a mutating function (`SetDisplayNameForLoadout`) succeeded cleanly on the first instance but **crashed the game on the second, identical call to the second instance**. Reads are safe on both; writes are only confirmed safe on the first. Until root-caused, **mod code should only call mutating functions on one `LoadoutComponent` instance** (e.g. `components[1]`, or find a way to identify the real player-owned one), not loop over all of `FindAllOf(...)` blindly for write operations.

---

## `Widget_LoadoutsPanel` (`/Game/UI2/UI_Widgets/UI_Game/UI_Game_Character/Widget_LoadoutsPanel`) — found the real tile-count driver

Inspected via FModel's "Save Folder's Packages Properties .JSON" dump (`Widget_LoadoutsPanel.json`, in repo root). This is the parent panel widget that lays out all the loadout tiles.

**Key function: `Refresh`**. Its reflection-only property list (compiled temp-variable names, not the visual graph, but readable) shows the flow:

1. `CallFunc_GetLoadoutComponent_Loadouts` — gets the live `LoadoutComponent`.
2. `CallFunc_GetMaxRecordsForTemplate_ReturnValue` — calls a function named `GetMaxRecordsForTemplate` (not a raw property read of `Slots[].NumRecords`).
3. `CallFunc_Subtract_IntInt_ReturnValue` then `CallFunc_Clamp_ReturnValue` — some adjustment/clamp applied to that count.
4. `CallFunc_GetChildrenCount_ReturnValue` compared against it, then loop: `CallFunc_Create_ReturnValue` (spawns a new `Widget_Loadout_C` tile) → `CallFunc_AddChild_ReturnValue` (adds it to the panel), presumably until the child count matches the clamped max.

**This resolves the earlier dead end**: our `NumRecords = 20` write (see above) had no visible effect because the UI doesn't read that field directly — it goes through `GetMaxRecordsForTemplate`, a function call whose internal logic we haven't seen yet. It might simply return `NumRecords` (in which case our test's *timing* was the problem — we patched after `Refresh` had already built the panel once) or it might compute/cap the value independently of the raw field (DLC gating, a hardcoded constant, etc.).

**Next step**: call `GetMaxRecordsForTemplate` directly from Lua on the live `LoadoutComponent` and log its return value, same reflection-call pattern already proven safe for `GetDisplayNameForLoadout`. Compare the value before and after patching `NumRecords`, to determine which of the two theories above is correct.

### Confirmed: `GetMaxRecordsForTemplate` is a pure passthrough of `NumRecords`

Tested live, both `LoadoutComponent` instances, no crash:

```
GetMaxRecordsForTemplate (before patch) = 11
patched NumRecords to 20
GetMaxRecordsForTemplate (after patch) = 20
```

Not capped by DLC/unlocks/a hardcoded constant — it just reads the field. So the earlier "patching `NumRecords` had no visible in-game effect" result (see above) was almost certainly a **stale-UI/timing issue**, not evidence the value is disconnected from the UI. The Loadouts screen widget needs to freshly (re)construct/`Refresh` *after* the patch to pick up the new value — if it was already open/built before the patch landed, it wouldn't have re-read anything.

**Mod #1 is very likely just a straightforward `NumRecords` property patch.** Next real test: patch on `ClientRestart`, then open the Loadouts screen for the first time that session (not a screen that was already cached open before the patch), and check whether more than 8 saveable slots now appear.

### Retested cleanly — still capped at 8. Traced to a hardcoded clamp, confirmed via live tile count

Full relaunch, `NumRecords` patched to 20 on `ClientRestart`, opened the Loadouts screen fresh for the first time that session. **Still exactly 8 saveable slots.** So the earlier "stale UI" theory was wrong too — something is actively capping the tile count regardless of the underlying data.

Searched UE4SS Live View for all live `Widget`-named instances while the loadout overlay was open (filters: "Include CDOs" off, "Instances only" on — cuts template/CDO noise). Results dumped to `WidgetSearchResults.txt` (~10.8MB) and grepped for "Loadout". Found:

- `Widget_LoadoutsPanel_C` confirmed live at `Widget_Character_C → Widget_Equipment_Stats_C → Widget_LoadoutsPanel_C` — real hierarchy. The double-tap-R overlay is likely a shortcut into this same underlying Character-menu widget tree rather than a separate widget system (plausible, not 100% proven).
- **Exactly 8** live `Widget_Loadout_C` tile instances exist (`_2147477340` through `_2147477200`, sequential), plus a separate `LastLoadoutSlot` instance for the 9th non-saveable tile — matching the visible count exactly, despite `GetMaxRecordsForTemplate` correctly reporting 20.

**Conclusion**: `Widget_LoadoutsPanel_C.Refresh`'s `Subtract`/`Clamp` step (see above) hardcodes a max of 8 — a literal value baked into the compiled Blueprint function, not a property we can patch with `SetPropertyValue`. Mod #1 now needs a **behavioral hook** (e.g. `RegisterHook` on `Refresh`, then manually replicate its `CreateWidget`/`AddChild` calls from Lua for indices 8+) rather than a simple data patch. Still very achievable, just one step harder than hoped.

### The tile container is also a fixed size — `SizeBox_0.HeightOverride = 688`, no `ScrollBox`

Traced the static widget tree (not a function, the actual design-time hierarchy) to see where new tiles get added: a `VerticalBox` named `LoadoutList`, with **no design-time children at all** — entirely populated at runtime. It's nested inside a `SizeBox` (`SizeBox_0`) with `HeightOverride = 688.0` (`bOverride_HeightOverride = true`) — a hardcoded fixed pixel height. No `ScrollBox` exists anywhere in the widget's tree (confirmed via full-file grep).

688px / 8 visible tiles ≈ 86px/tile. So beyond the `Refresh`-loop clamp fix, we'll also need to patch `SizeBox_0.HeightOverride` proportionally (roughly `86 * desired tile count`) so extra tiles have room instead of overflowing/spilling past the box's fixed bound. `HeightOverride` is a normal overridable UMG property though, not compiled logic — patchable with the same `SetPropertyValue` mechanism already used successfully elsewhere.

**Mod #1, full picture now**: (1) patch `NumRecords` upward — confirmed working, proxies correctly through `GetMaxRecordsForTemplate`; (2) hook `Widget_LoadoutsPanel_C:Refresh` to push its tile-creation loop past the hardcoded clamp of 8 — needs the exact `CreateWidget`/`AddChild` call shape, next step; (3) patch `SizeBox_0.HeightOverride` to match the new tile count.

---

## `Widget_Loadout` (`/Game/UI2/UI_Widgets/UI_Game/UI_Game_Character/Widget_Loadout`, singular) — the per-tile widget's spawn/init recipe

FModel property-JSON dump (`Widget_Loadout.json`, repo root). Class-level variables that matter for recreating a tile programmatically:

- **`Index`** (int) — `ExposeOnSpawn`. Set as a `CreateWidget` spawn parameter, not a post-construction call.
- **`LoadoutTemplate`** (object ref to a `LoadoutTemplate` asset) — plain `Edit | BlueprintVisible` property, no `ExposeOnSpawn`. Set via a normal property write after the widget exists — same write mechanism already proven safe for `NumRecords`/`HeightOverride`.
- **`OnClicked`** — `BlueprintAssignable` multicast delegate, bound after construction.
- The tile has its own **`Refresh` function**, which reads `Index` + `LoadoutTemplate` (+ a locally-fetched `LoadoutComponent`) to build its label text (`Add_IntInt` → `Conv_IntToText` → `Format`, i.e. "Loadout N" built from `Index`) and icons. Calling this after setting the two properties should make a manually-built tile self-populate.

**Recipe for mod #1's extra tiles**: construct a new `Widget_Loadout_C`, set `Index`/`LoadoutTemplate`, call its `Refresh`, `AddChild` it into `LoadoutList`, bind `OnClicked`. Each of these individual steps mirrors something already done safely this session (property writes, function calls with simple params) — but chained together as new-object-construction + container-mutation, it's a meaningfully bigger and riskier step than anything attempted so far. Build and test incrementally, not as one script — same lesson learned the hard way from the `SetDisplayNameForLoadout`/`FText` crash earlier.

### MILESTONE — confirmed working end-to-end, a real extra tile renders correctly in-game

Built incrementally, one step verified at a time: construct `Widget_Loadout_C` → set `Index=8`/`LoadoutTemplate` → call the tile's own `Refresh()` → `AddChild` into the panel's `LoadoutList` → resize the container via `SizeBox_0:SetHeightOverride(774)`. No crash at any step. Final in-game result: a properly-spaced "Loadout 09 — Empty" tile, correct hover tooltip, no overlap with "Last Gear State".

Two tooling lessons from getting here:
- `SizeBox.HeightOverride = X` as a raw property write succeeds (reads back correctly) but has **no visible effect** — UMG/Slate caches layout state in the native widget, and only the real setter function (`SetHeightOverride(float)`) triggers a re-layout. Property writes work for data (`NumRecords`), not always for visual layout — call the actual function instead.
- `NotifyOnNewObject` hooks appear to only reliably fire after the first hot-reload of a play session — a fresh launch's first screen-open doesn't trigger them even though the screen renders fine. Not root-caused, but consistent across 3+ tests. Workaround: always do one throwaway hot-reload right after a full relaunch before relying on `NotifyOnNewObject`.

**Not yet done**: this only adds one hardcoded tile (index 8). Still need: (1) a loop for indices 8 through the new `NumRecords - 1`, (2) a guard against duplicate tiles piling up since the hook fires on every `Refresh` call (reopening the screen right now would keep adding more), (3) binding `OnClicked` so the tile is actually interactive (currently only the hover tooltip works; right-click/save does nothing).

### Why the tile ignored clicks: `Widget_Loadout_C` has a `ComponentDelegateBinding` that only `CreateWidget` applies

The tile's click handling isn't via `OnClicked`/`OnInputAction` wiring we'd do ourselves — the FModel dump's first object is a `ComponentDelegateBinding` on the class mapping the tile's internal `Button` (`FocusButtonWidget` in its WidgetTree): `OnMouseRightClick` → save handler, `OnClicked` → load handler, `OnMouseEnter`/`OnMouseLeave` → hover handlers. These dynamic bindings are applied by `UUserWidget::Initialize()` — native, non-reflected, not callable from Lua — which `CreateWidget` runs and `StaticConstructObject` skips. Tooltip worked anyway because it's pull-based (`GetValidInputActions` via `BPI_TooltipAction_Interface`); clicks are push-based delegates that were never bound. Manually calling `Construct()` was tested and does NOT fix it (binding lives in `Initialize`, not `Construct`).

**Fix (implemented, pending in-game test)**: create the tile with `WidgetBlueprintLibrary.Create` (the engine function behind the Blueprint "Create Widget" node — the same call the panel's own `Refresh` makes): `StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")` → `wbl:Create(panel, tileClass, playerController)`. Full lifecycle runs, bindings included; also removes the need for manual unique naming and the manual `Construct()` call.

**Test result: partial.** Tile renders, and the tooltip's RMB indicator now lights up on right-click (input reaches the tile's button — progress vs. `StaticConstructObject`), but no save dialog appears.

### Second missing piece: the panel subscribes to each tile's delegates — the dialogs are the panel's, not the tile's

The tile never saves anything itself — it only broadcasts (`OnClicked`, `OnLoadoutSaved`, `OnLoadoutSlotDeleted`). All dialog machinery (`BeginDialog`, `Dialog_GenericWait_C`, `DeleteDialogResult`) is in `Widget_LoadoutsPanel_C`, whose `Refresh` binds its three handlers (`OnLoadoutClicked`, `OnLoadoutSlotSaved`, `OnLoadoutSlotDeleted` — all in its FuncMap) to every tile it creates, via `K2Node_CreateDelegate` (visible in the panel graph's locals). Our tile broadcast into the void.

**Binding from Lua FAILED — hard UE4SS limitation.** Merely reading `newTile.OnClicked` raised `[handle_unreal_property_value] ... Property type 'MulticastInlineDelegateProperty' not supported`, and the error aborted the whole callback *despite pcall* (tile never got added). The installed UE4SS build has no Lua handler for multicast delegate properties; the `:Add` syntax exists only in the dev-branch docs. Workaround options (see research doc 3.4p): (1) post-hook the tile's own `BndEvt` right-click handler and call `panel:OnLoadoutSlotSaved(Index)` directly; (2) upgrade UE4SS; (3) switch mod #1 to a Blueprint-asset patch. **Option 1 chosen and implemented.**

### Click forwarding via hooks on the tile's bound-event handlers (implemented, pending test)

`self:get()` confirmed safe in-game (ZZTestMod test, 3 hover runs — unwrap, `IsValid`, `GetFullName`, `.Index` read all fine, including on the mod's own created tile). MoreLoadoutSlots now post-hooks `Widget_Loadout_C:BndEvt__..._0_OnFocusMouseEventDelegate...` (right-click) and `BndEvt__..._2_OnAdvButtonClickedEvent...` (left-click), registered lazily at first tile creation. Hook flow: `self:get()` → match `GetFullName()` against a registry of this mod's created tiles (native tiles skipped — their clicks already reach the panel; forwarding would double-fire) → read `.Index` → call `currentPanel:OnLoadoutSlotSaved(Index)` / `OnLoadoutClicked(Index)` (both confirmed to take one int parm). `currentPanel` is refreshed on every panel construction. Note: `Create`-made tiles are outered to `BP_RemnantGameInstance_C`, not the panel — identity matching must use the name registry, not Outer.

### MILESTONE — the 9th slot is fully functional (renders, saves, loads)

Click forwarding confirmed in-game: right-click → real "SAVE LOADOUT?" dialog → working save; left-click → working load. Mod #1's core mechanism is complete. Remaining: verify the saved loadout survives a full game relaunch; generalize 1 tile → N (no ScrollBox exists, so tile size/count must respect the fixed panel area); fix the `NotifyOnNewObject` needs-one-hot-reload-after-launch quirk before the mod is shippable.
