# Remnant 2 Modding — Research & Planning Doc

*Living document. Keep appending as we learn more — don't delete earlier sections, mark them outdated if superseded.*

---

## 1. Project Goals

Three mod ideas, roughly in priority order:

1. **Increase number of loadout slots**
2. **Name loadout slots**
3. **Search bar for rings/amulets in inventory** (previously started, dropped)

Modder background: some hex editing experience, a little Blueprint modding in Unreal Engine. Beginner overall — plan should build up skills incrementally rather than assume prior UE project experience.

---

## 2. Toolchain Landscape (initial research pass)

### Engine
- Remnant 2 runs on Unreal Engine 4/5-family, using **IOStore** (`.ucas`/`.utoc` files present in the Paks folder). This matters because it changes the packaging process — old-style loose `UnrealPak` packaging isn't enough; you need chunk assignment / IOStore-aware cooking if you go the full asset-replacement route.

### Primary source used for general UE modding literacy
- [Dmgvol/UE_Modding](https://github.com/Dmgvol/UE_Modding) — general-purpose UE4/5 modding guide collection, not game-specific. Structure:
  - **TheBasics/** — extracting game files, browsing assets, exporting models/animations
  - **BasicModding/** — changing Blueprint default values, editing `.umap`s (via tool called "Stove" — supports duplicating actors, editing spawn-instance default values)
  - **IntermediateModding/** — creating a matching UE project (must be named exactly like the game's project — check the game's largest `*-Shipping.exe` for the binary name), packaging/cooking settings (must disable "Share Material Shader Code"), dummying/replacing assets (textures, materials, meshes, skeletal meshes)
  - **AdvancedModding/** — **injecting custom Widgets into game menus using Blueprints** (this is the technique most relevant to loadout-naming and inventory search bar), speedrun/randomizer/trainer-style logic
  - **BPModding/WorkingWithML.md** — explains mod loader conventions: UML and UE4SS use DLL injection; DML is a pak-based loader needing no third-party software. BP mods live at `/Mods/<ModName>/`, main blueprint must be named `ModActor`, uses `PreBeginPlay`/`PostBeginPlay` (or default `BeginPlay`) lifecycle methods.
  - Tools referenced: UAssetGUI, UAssetAPI (by atenfyr), UnrealModLoader (by RussellJerome)
  - Caveat: this guide is generic across UE games — Remnant 2-specific class names, widget hierarchies, and save structures are **not** in this guide and must come from community/Discord/reverse engineering.

### Remnant-2-specific tooling (from broader web research)
- **RE-UE4SS** ("UE4SS") — injectable Lua scripting system + SDK generator + live property editor for UE4/5 games. This is the dominant modding backbone for Remnant 2 specifically. GitHub: `UE4SS-RE/RE-UE4SS`.
- **"Allow Asset Mods"** (Nexus Mods, remnant2/mods/2) — the de facto required base install for the Remnant 2 modding scene. Bundles:
  - A custom/unreleased build of UE4SS
  - A console enabler
  - A blueprint mod loader
  - Install path: extract into `Steam\steamapps\common\Remnant2\Remnant2\Binaries\Win64` (or WinGDK path for Xbox/Game Pass)
  - Config toggle: `Remnant2\Remnant2\Binaries\Win64\Mods\mods.txt` — set lines to 0 to disable console enabler or BP mod loader individually
  - Notes pak-only config-edit mods do **not** affect multiplayer join ability; DLL-injection-based mods (like this one) have occasionally caused compatibility hiccups (e.g., a period where `xinput1_3.dll` caused startup crashes for some users, fixed by community workaround / later patched)
  - Steam Deck/Linux: not officially supported as of source mod's writing; there's a beta UE4SS build referenced for Linux/Deck compatibility
- **Community Discord**: `discord.gg/jX5qd2RefK` — described as the hub "to discuss Remnant 2 and other Gunfire Games modding." This is likely where actual class paths, widget names, and save-data structure knowledge is shared, since it isn't published in any single guide.

### Existing community mods (evidence of what's been done, and how)
Nearly all of these are **UE4SS Lua script mods** — folder structure is consistently `Mods/<ModName>/Scripts/main.lua` (+ `config.lua`, `enabled.txt`, sometimes a `.dlls/main.dll` C++ variant):

| Mod | What it does | Method |
|---|---|---|
| Remnant 2 Spawner UI / Item Spawner UI (`EX0Sk1tz/Remnant-2-item-spawner-UI`) | External standalone .NET app with searchable item database; spawns items via UE4SS bridge + `CheatManager`, or via console `summon` command | External app + UE4SS bridge (not an in-game widget injection) |
| UE4SS Trait Custom (Remnant: From the Ashes, same modder scene/technique carries to R2) | Edit trait parameter values via a Lua `config.lua` | Pure Lua value editing, no UI |
| UE4SS Auto Loot Drop Item | Auto-picks up dropped items/chest loot | Lua, hooks pickup detection |
| UE4SS Skin Change / Armor Transmog (`AuriCrystal`'s Armor Transmog for R2, and `VoodkaVina`'s R2tA skin change mod which explicitly credits learning from AuriCrystal's Lua) | Visual-only armor swap independent of equipped stats | Lua, hooks character appearance assignment; in-game console commands like `skinchange.setall <SetName>` |

**Key finding: nobody has published an in-game UI widget injection mod for Remnant 2** (no loadout-slot mod, no in-game inventory search bar — the "Spawner UI" is an external app, not an injected widget). This means our search bar and loadout-naming ideas would be somewhat novel for the public scene — good reason to lean on the Discord community and to reverse-engineer the AdvancedModding/widget-injection technique from the Dmgvol guide directly, since there's no existing R2-specific example to copy.

The community *wants* the loadout slot feature — found explicit player requests on Steam discussions for "simple loadout slots" as a quality-of-life fix, confirming demand but also confirming nobody's solved it yet.

### Mapping our 3 mod ideas to method (initial hypothesis, to be refined after code pull-apart)

| Idea | Likely approach | Reasoning |
|---|---|---|
| More loadout slots | Blueprint/asset edit (UAssetGUI/Stove) to extend an array/struct size, **plus** UI layout change to render the extra slots | Probably not just a number — likely a fixed-size array bound to a fixed set of UI slot widgets |
| Name loadout slots | UE4SS Lua widget injection — inject a text input widget on the loadout screen; persist names via a Lua-side config file (simplest) or hook save data (more integrated but riskier) | Matches "inject custom Widgets into game menus using Blueprints" technique in the Advanced guide |
| Ring/amulet search bar | Same widget-injection pattern — inject a text field above inventory grid, hook into the list population/filtering logic | Same technique as #2; good code reuse opportunity |

**Both #2 and #3 point to the same core skill: UE4SS Lua + Blueprint widget hooking.** Plan to standardize on UE4SS Lua mods as primary method rather than full `.pak` blueprint replacement, since iteration is much faster (no repackaging/relaunch cycle per change).

---

## 3. Pull-Apart Task: How existing Remnant 2 Lua mods actually work

### 3.1 The core UE4SS Lua API (the actual mechanism, not just folder structure)

This is the piece the earlier pass was missing — *how* a Lua mod reaches into the game at all. Four functions do almost all the work across every example found (Remnant 2, Palworld, Hogwarts Legacy modding docs all converge on the same pattern, confirming it's a general UE4SS idiom, not per-game magic):

- **`StaticFindObject(path)`** — finds an object (usually a *class default object*, e.g. `Default__SomeItem`) that already exists in memory by its full path. Used to read/write default property values directly.
- **`RegisterHook(path, callback)`** — hooks a `UFunction` so `callback` fires after it runs. **Critical constraint: the target UFunction must already exist in memory when you register the hook** — this is why almost every mod hooks `/Script/Engine.PlayerController:ClientRestart` first (fires on character spawn/respawn, both singleplayer and co-op), and does its real work *inside* that callback.
- **`NotifyOnNewObject(path, callback)`** — fires whenever a new instance of a class is constructed. Unlike `RegisterHook`, the class does **not** need to exist yet when you register it. This is how mods reliably catch dynamically-created things — including **UI widgets that don't exist until a menu opens** — which is exactly the mechanism our loadout/search-bar mods will need.
- **`ExecuteInGameThread(fn)`** — wraps the actual mutation logic; property/function calls on live UObjects generally need to happen on the game thread.

Common nesting pattern seen across every real-world example (Palworld docs, Hogwarts Legacy community scripts, and the Remnant 2 "ModifyStat" reference below all use this same shape):

```lua
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(Context, NewPawn)
  ExecuteInGameThread(function()
    -- do the actual work here, now that we know a player/world exists
    NotifyOnNewObject("/Game/Path/To/SomeWidget.SomeWidget_C", function(WidgetInstance)
      -- runs every time that specific widget is constructed (e.g. menu opened)
    end)
  end)
end)
```

### 3.2 Real Remnant 2 example (from a community "Modding 101" README, ShadowChaosTime/Nexus mod #167, crediting AuriCrystal & "Pokémon Professor Vokun")

This is a genuine beginner-facing script-mod tutorial from the R2 community, with a concrete working example — worth treating as closer to ground truth than the generic Dmgvol guide for R2-specific paths:

```lua
function ModifyStat (asset, name, value)
  local Item = StaticFindObject(asset)
  if not Item:IsValid() then return end
  Item:SetPropertyValue(name, value)
end

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(self, NewPawn)
  ExecuteInGameThread(function()
    ModifyStat(
      "/Game/World_Nerud/Items/Trinkets/Amulets/Hyperconductor/Amulet_Hyperconductor.Default__Hyperconductor",
      "HeavyWeaponAmmoMod",
      69
    )
  end)
end)
```

What this teaches us concretely:
- **Real R2 asset path structure confirmed**: `/Game/World_<Zone>/Items/<Category>/<Subcategory>/<ItemName>/<AssetFile>.Default__<ClassName>` — e.g. amulets live under `/Game/World_Nerud/Items/Trinkets/Amulets/...`. Rings appeared elsewhere in our search results as `/Game/World_Base/Items/Trinkets/Rings/...`. This gives us a real naming convention to anticipate when we go hunting for loadout-related classes.
- `SetPropertyValue(name, value)` is the write path for simple property edits on a found object — this is likely how a "loadout slot count" constant could be patched *if* it's exposed as a simple property on some default object, rather than buried in UI layout.
- The mod loader folder convention is confirmed independently: `Mods/<ModName>/enabled.txt` + `Mods/<ModName>/Scripts/main.lua` (capital-S "Scripts" appears in most real mods; lowercase "scripts" appears in this beginner README — both seem to work, but match what a given base install expects).

### 3.3 Discovery tooling — how modders actually find these paths (we don't get to guess)

The "Modding 101" README and other sources converge on the same toolchain for figuring out class/property names before writing any hook:

- **FModel** (fmodel.app) — asset browser/dumper for UE .pak/.ucas/.utoc archives. Modders use a community-shared **mapping file** (`.usmap`) specific to Remnant 2, distributed via the modding Discord, to get FModel to resolve real property/class names instead of obfuscated ones. Right-click → "Save Folder's Packages Properties .JSON" dumps parsed structure to JSON, which can then be searched with a text editor/regex.
- **UE4SS Live View / debugger** — built into UE4SS itself. Lets you browse live Blueprint instances *while the game is running* and see real property values and paths, including UI widget hierarchies. This is the recommended way to find the specific widget class name for something like the loadout screen, since it's live and in-context rather than static-file archaeology.
- **UE4SS SDK generator** — can dump a full C++-style SDK of the game's UE classes, useful as a searchable reference once generated for our specific installed game version.

**Practical conclusion for our 3 mods**: before writing a single hook, we need to (1) get UE4SS running with Live View enabled, (2) get FModel + the community R2 mapping file, and (3) actually open the loadout screen and inventory screen in-game with Live View active to find the real widget class names, property names, and array sizes involved. No guide — generic or R2-specific — is going to hand us the literal loadout-widget class name; that's a "go look at the live object tree ourselves" task, ideally cross-checked against the modding Discord in case someone's already documented it.

### 3.4 CONFIRMED — Live inspection of `LoadoutComponent` (loadout slot count)

Live Lua inspection (via `FindAllOf("LoadoutComponent")` + reading `.Slots` array on the character's live component, using `ZZTestMod` as a scratch script, since UE4SS's Live View GUI only exposes *reflection metadata* for FProperty nodes — offsets/flags/types — not actual runtime values; needed to read via Lua + log instead) on the player character's live `LoadoutComponent` (`/Game/Maps/Main.Main:PersistentLevel.Character_Master_Player_C_<instanceID>.Loadout`) confirmed:

- `LoadoutComponent.Slots` has exactly **one entry**, `Template = /Game/_Core/Loadouts/Gear_Loadout` (a `LoadoutTemplate` asset), with **`NumRecords = 11`**.
- **CORRECTED (was wrong above, then re-corrected): the in-game UI actually shows 8 saveable loadout slots, plus one additional non-saveable "Last Gear State" slot** (visually confirmed by the user in-game) — not 3, as originally assumed going into this investigation. That's 9 visible slots against a cap of 11 — much closer to the data-layer limit than first thought.
- **Revised hypothesis, replacing the "pure UI problem" theory above**: since the visible slot count (8, or 9 counting "Last Gear State") tracks so closely with `NumRecords = 11`, the UI panel (`Widget_LoadoutsPanel_C`) is very likely **already dynamically built from `NumRecords`/a related count function** (e.g. `GetMaxRecordsForTemplate`), rather than hardcoded to a fixed tile count. If true, this is great news: mod #1 may reduce to the "easy property patch" case flagged as best-case back in section 3.2 — i.e. **just increasing `NumRecords`** (wherever that value actually originates — see open question below) could make the existing UI panel render more slots automatically, with no widget/layout work needed at all.
- **New critical open question, superseding the "is the UI hardcoded" question below**: where does `NumRecords = 11` actually come from? Options: (a) a property directly on the `Gear_Loadout` `LoadoutTemplate` asset (easy `SetPropertyValue` patch, same pattern as the amulet example in 3.2), (b) computed elsewhere in `LoadoutComponent` logic (e.g. based on DLC ownership/unlocks), or (c) a hardcoded engine-side constant. Needs tracing — likely via FModel on the `Gear_Loadout` asset itself, or via `GetMaxRecordsForTemplate`'s Blueprint graph if it's not a plain property.
- Also found: `Widget_LoadoutsPanel_C` at `/Game/UI2/UI_Widgets/UI_Game/UI_Game_Character/Widget_LoadoutsPanel.Widget_LoadoutsPanel_C` — has its own `GetLoadoutComponent()` function, same pattern as `Widget_Loadout_C` (the per-tile widget). Strong candidate for the parent container that lays out the 3 visible loadout tiles. Not yet inspected for whether its child list is a hardcoded fixed-size layout or a loop over an array/count.
- Minor unexplained curiosity, not yet investigated: two live `LoadoutComponent` instances showed up in the same query, on two different `Character_Master_Player_C` instance IDs, both with identical `Slots` data. Possibly a listen-server client/server duality (even singleplayer R2 runs as a local listen server) rather than two real characters — not blocking, but worth keeping in mind if duplicate-instance confusion shows up again.

### 3.4f CONFIRMED — `Widget_LoadoutsPanel_C.Refresh` builds tiles from `GetMaxRecordsForTemplate`, not raw `NumRecords`

FModel property-JSON dump of `Widget_LoadoutsPanel_C` (`Widget_LoadoutsPanel.json`, saved to repo root) confirms this widget's `Refresh` function is the real tile-count driver. It's a reflection-only dump (temp-variable names from the compiled function, not the visual graph), but the naming makes the flow readable:

1. `CallFunc_GetLoadoutComponent_Loadouts` → gets the live `LoadoutComponent`.
2. `CallFunc_GetMaxRecordsForTemplate_ReturnValue` → calls a `GetMaxRecordsForTemplate`-named function (not a raw `NumRecords` field read).
3. `CallFunc_Subtract_IntInt_ReturnValue` → `CallFunc_Clamp_ReturnValue` → some adjustment/clamping of that count.
4. `CallFunc_GetChildrenCount_ReturnValue` compared against the clamped count, then a loop: `CallFunc_Create_ReturnValue` (creates a new `Widget_Loadout_C` tile) → `CallFunc_AddChild_ReturnValue` (adds it to the panel) for each tile still missing.

**This explains the earlier "NumRecords=20 write did nothing" result**: the UI never reads `Slots[].NumRecords` directly — it goes through `GetMaxRecordsForTemplate`, a function call that may or may not simply return `NumRecords` under the hood. This is the real mod #1 hook candidate.

**Next test**: call `GetMaxRecordsForTemplate` from Lua on the live `LoadoutComponent` (same reflection-call pattern already proven safe for `GetDisplayNameForLoadout`) and log its return value — both before and after patching `NumRecords` — to see whether it tracks the raw field or is computed/capped independently (e.g. by DLC ownership or a hardcoded constant). If it just proxies `NumRecords`, the timing of our earlier test is the likely culprit (patched after `Refresh` had already run once) and a hook that patches *before* the panel opens should work. If it's independent, we'll need to find where its own value comes from.

### 3.4g CONFIRMED — `GetMaxRecordsForTemplate` directly proxies `NumRecords`

Test result (both `LoadoutComponent` instances, no crash):

```
Slot 1: GetMaxRecordsForTemplate (before patch) = 11
Slot 1: patched NumRecords to 20
Slot 1: GetMaxRecordsForTemplate (after patch) = 20
```

The function is a pure passthrough of the raw field — not independently capped by DLC/unlocks/a hardcoded constant. **This means the earlier "NumRecords=20 write had no visible UI effect" result was a stale-UI/timing artifact, not a wrong hypothesis.** The write happens on `ClientRestart`, but if the Loadouts screen widget was never freshly (re)constructed after that write during that test, `Refresh` wouldn't have re-run against the new value.

**Mod #1 is very likely just a `NumRecords` property patch after all** — the originally-hoped-for easy case. Next step: retest cleanly — patch `NumRecords` on `ClientRestart` (already happening in `ZZTestMod`), then explicitly open the Character > Loadouts screen for the *first time that session* (not just re-checking a screen that was already open/cached before the patch) and see if more than 8 saveable slots appear.

### 3.4h CONFIRMED (superseding 3.4g's optimism) — tile count is hardcoded to 8, independent of `NumRecords`/`GetMaxRecordsForTemplate`

Retested cleanly per 3.4g's plan: full relaunch, `NumRecords` patched to 20 on `ClientRestart`, then opened the Loadouts screen fresh. **Still only 8 saveable slots** — no change.

To find out *why*, searched UE4SS Live View for all live `Widget` instances while the loadout overlay was open (search "Widget", with "Include CDOs" unchecked and "Instances only" checked to filter out templates/defaults — results dumped to `WidgetSearchResults.txt`, ~10.8MB, too large to read directly; grepped for `Loadout`). Findings:

- `Widget_LoadoutsPanel_C` is confirmed genuinely live, nested at `Widget_Character_C → Widget_Equipment_Stats_C → Widget_LoadoutsPanel_C` — real hierarchy, not a guess. Strongly suggests the double-tap-R quick-access overlay is a shortcut into this same underlying Character-menu widget tree, not a separate implementation (not fully proven, but no longer a live risk to the investigation).
- Exactly **8** live `Widget_Loadout_C` tile instances exist at runtime (`Widget_Loadout_C_2147477340`, `_320`, `_300`, `_280`, `_260`, `_240`, `_220`, `_200` — sequential creation order, spaced by 20, parented directly to `BP_RemnantGameInstance_C` as is typical for freshly-`CreateWidget()`'d widgets before `AddChild` reparents them), plus one separate `LastLoadoutSlot` instance for the 9th non-saveable tile.
- **This confirms the `Refresh` function's `Subtract`/`Clamp` step (3.4f) hardcodes a max of 8 tiles**, independent of `GetMaxRecordsForTemplate`'s actual return value (confirmed correctly returning 20 in 3.4g). The loop simply never runs past 8 iterations, regardless of what the live data says the cap should be.

**What this means for mod #1**: the clamp is baked into the compiled Blueprint function (a literal pin value on a `Clamp` node), not a property we can patch with `SetPropertyValue`. A direct data patch isn't enough — we need a **behavioral hook**: `RegisterHook` on `Widget_LoadoutsPanel_C:Refresh` (pre or post) and, from Lua, manually call `CreateWidget`+`AddChild` extra times to mimic what the loop does for indices 8+, OR find whatever function underlies `Clamp`'s literal max and intercept/override its return via a hook rather than editing the property. Both need the `Refresh` function's actual container/parent-slot logic understood a bit more first (which panel/container the new tiles get added to, and whether that container's layout supports more than 8 without additional layout work).

### 3.4i CONFIRMED — the tile container has a hardcoded fixed height too (`SizeBox_0.HeightOverride = 688`), no `ScrollBox` anywhere

Traced the widget tree (not the function, the static design-time hierarchy) to find where `Refresh`'s `AddChild` calls actually land: a `VerticalBox` named `LoadoutList`, which has **zero static/design-time children** — it's populated entirely at runtime by the loop. `LoadoutList` sits inside a `SizeBox` (`SizeBox_0`) with `HeightOverride = 688.0` and `bOverride_HeightOverride = true` — a hardcoded fixed pixel height. Grepped the whole file for `ScrollBox`: **none exists** anywhere in this widget's tree.

**Implication**: even after successfully hooking `Refresh` to create more than 8 tiles, they'd overflow `SizeBox_0`'s fixed 688px bound rather than scroll — `SizeBox` doesn't clip by default, so extra tiles would likely spill out visually past the box rather than simply being invisible, but either way it'd look broken without a fix.

**The fix is still simple, though**: `HeightOverride` is a normal overridable UMG property, not compiled-in logic — patchable with `SetPropertyValue` exactly like `NumRecords` was. 688 / 8 tiles ≈ 86px/tile, so the new height for N tiles is roughly `86 * N`. No `ScrollBox` injection needed for a modest slot-count increase.

**Mod #1's real shape, now three coordinated pieces**:
1. Patch `LoadoutComponent.Slots[1].NumRecords` upward (already confirmed to work, proxies through `GetMaxRecordsForTemplate` correctly).
2. Hook `Widget_LoadoutsPanel_C:Refresh` to make the tile-creation loop go past its hardcoded clamp of 8 (still needs the exact `CreateWidget`/`AddChild` call shape — next investigation step).
3. Patch `SizeBox_0.HeightOverride` proportionally to the new tile count, so the extra tiles have room to render without overflowing/spilling.

### 3.4j CONFIRMED — `Widget_Loadout_C`'s class variables reveal the tile-creation recipe

FModel property-JSON dump of `Widget_Loadout_C` itself (`Widget_Loadout.json`, repo root — the per-tile widget, singular, distinct from `Widget_LoadoutsPanel.json`). Its class-level (not function-local) variables:

- **`Index`** (`IntProperty`) — `PropertyFlags: Edit | BlueprintVisible | ExposeOnSpawn`. `ExposeOnSpawn` means this is set as a spawn parameter directly on the `CreateWidget` call itself (the "Class Defaults" pins UMG exposes on a Create Widget node when a variable has this flag), not via a separate call after construction.
- **`LoadoutTemplate`** (`ObjectProperty`, `LoadoutTemplate` class) — `PropertyFlags: Edit | BlueprintVisible | DisableEditOnInstance`, no `ExposeOnSpawn`. Set via a plain property write after construction — same `SetPropertyValue` mechanism already used safely for `NumRecords`.
- **`OnClicked`** — `MulticastInlineDelegateProperty`, `BlueprintAssignable`. Bound post-construction (matches the panel's own `K2Node_CreateDelegate_OutputDelegate_1` step seen in `Widget_LoadoutsPanel_C`'s `Refresh`).
- The tile has its **own `Refresh` function** (`Widget_Loadout.json` line ~1513), which reads `Index` + `LoadoutTemplate` + a component reference to build its own display text/icons (uses `Add_IntInt` → `Conv_IntToText` → `Format` — i.e. builds "Loadout N" style label from `Index`). Calling this after setting `Index`/`LoadoutTemplate` should make a manually-created tile self-populate.

**Scope flag for the user**: everything up to this point (`NumRecords`, `HeightOverride` patches) has been simple property writes — the safest, most-proven operation this session. Actually implementing "create extra tiles past the hardcoded clamp" requires constructing a new `Widget_Loadout_C` instance, setting an `ExposeOnSpawn` param, adding it to a live container (`AddChild`), and calling a function on it — meaningfully higher complexity and crash risk than anything done so far (closer to the `SetDisplayNameForLoadout`/`FText` crash territory than the `NumRecords` territory). Should be built and tested incrementally, one small piece at a time, not attempted as a single script.

### 3.4k Tooling notes learned while building the extra-tile logic incrementally

- **`NotifyOnNewObject`'s callback fires at raw construction time**, before the object's own bound widget variables (e.g. a `UserWidget`'s `LoadoutList`) have been initialized. Grabbing `panel.LoadoutList` immediately inside a `NotifyOnNewObject(ClassPath, function(panel) ... end)` callback returned a non-nil but `IsValid() == false` object — too early. Fix: only capture the object reference in `NotifyOnNewObject`, then do the actual work in a `RegisterHook` on that object's own `Refresh` function (or similar), which fires only after the widget has fully initialized itself.
- **`RegisterHook`'s single-callback form is pre/post depending on the path prefix**: per UE4SS docs, if the path starts with `/Script/` (a native/engine function) the single callback is a **pre**-hook (fires before the original runs); for any other path (Blueprint/asset-rooted, like `/Game/...`) the single callback is a **post**-hook (fires after). Confirmed this in practice — our hook on `Widget_LoadoutsPanel_C:Refresh` (a `/Game/...` path) fired after `Refresh` completed, as needed.
- **HAZARD, upgraded from "soft Lua error" to "confirmed native crash" — `RegisterHook`'s `self` parameter is not safe to touch at all.** First attempt: `self:GetFullName()` (a method call) didn't error, just silently returned `nil`, which then crashed a string concat with a catchable Lua runtime error (`attempt to concatenate a nil value`) — the game itself stayed up. Second attempt, after switching to `self.LoadoutList` (a plain property *access*, not a method call, on the theory that indexing would be safer than calling a method): **this crashed the game outright** — `UE4SS.log` just stopped mid-execution, the exact same signature as the earlier `SetDisplayNameForLoadout`/`FText` native crash (not something `pcall` can catch). **Conclusion: do not touch a `RegisterHook` callback's `self`/`Context` parameter at all** — not properties, not methods — at least not for a Blueprint (`/Game/...`-rooted) function hook. Whatever object wrapper UE4SS hands back for `self` in this context is unsafe to dereference in any way tried so far.
  - This ruled out the entire "hook `Refresh`, use `self` to identify the correct instance" approach. **Final working design**: never call `RegisterHook` on `Refresh` at all. Instead, rely solely on the `panel` object handed directly to a `NotifyOnNewObject` callback (proven safe every time this session, no exceptions) and poll for `panel.LoadoutList:IsValid()` becoming true using `LoopAsync(intervalMs, function() ... return true/false end)` (a documented UE4SS Lua global — return `true` to stop looping, `false` to keep polling) instead of relying on a hook to signal "the widget tree is ready now."
  - **ROOT CAUSE FOUND (after the fact, via UE4SS docs research)**: `self`/`Context` in a `RegisterHook` callback is wrapped in a `RemoteUnrealParam`, not handed over as a plain, ready-to-use UObject. Per UE4SS's own docs, hooked-function parameters (including the `self`/"this" pointer) live in the raw per-call argument frame (Unreal's `FFrame`-based parameter-passing for UFunction calls) rather than as a stable, independently-tracked object handle the way a normal `FindAllOf`/`NotifyOnNewObject`-sourced object is. `RemoteUnrealParam` is UE4SS's safety wrapper around that, and **the documented, correct access pattern is `self:get()`** (example from the docs: `local PlayerController = Context:get()`), which does the actual dereference into a normal, safely-indexable Lua object — only after which normal calls like `:GetFullName()` or `:IsValid()` are meant to be used. We never called `:get()` — we touched the raw wrapper directly both times (as a method call, then as a property access), which is exactly the unsafe path the wrapper exists to prevent. Confirmed via [UE4SS RegisterHook docs](https://docs.ue4ss.com/lua-api/global-functions/registerhook.html) and [RemoteUnrealParam docs](https://docs.ue4ss.com/lua-api/classes/remoteunrealparam.html); a related open bug ([UE4SS-RE/RE-UE4SS#933](https://github.com/UE4SS-RE/RE-UE4SS/issues/933), enum values >255 misreading through `:get()`) confirms this is a real, actively-used, occasionally-fiddly part of the API — not an obscure corner.
  - **RESOLVED — `self:get()` confirmed safe in-game (see 3.4q).** A dedicated ZZTestMod safety test (hook on `Widget_Loadout_C`'s mouse-enter bound-event handler, 3 runs) passed completely: `self:get()` returned the real tile instance, and `:IsValid()`, `:GetFullName()`, and a `.Index` property read all worked on the unwrapped object, no crash. The working rule is now: **inside a `RegisterHook` callback, always unwrap with `self:get()` before touching anything; never touch the raw wrapper.**
- **Observed but not confirmed root-caused: `NotifyOnNewObject` hooks seem to only reliably fire after the first hot-reload of a session.** On a genuinely fresh game launch, opening the Loadouts screen for the first time did not trigger our `NotifyOnNewObject` callback, even though the screen itself rendered normally. Doing one throwaway hot-reload immediately after launch, then reopening the screen, reliably triggered it every time this was tested (3+ occurrences). Practical workaround: always do one hot-reload right after a full relaunch before testing anything that depends on `NotifyOnNewObject`.
- **HAZARD — writing a UMG property directly (e.g. `SizeBox.HeightOverride = X`) doesn't always trigger a re-layout.** The write succeeds (no error, reads back correctly) but has no visible effect, because Slate caches layout state in the underlying native widget and only specific setter *functions* (e.g. `SetHeightOverride(float)`) invalidate that cache as a side effect. **When changing a UMG widget's visual layout property, call the real setter function, not a raw property write** — this is the same class of trap as the earlier `NumRecords`-vs-`GetMaxRecordsForTemplate` distinction, but for layout instead of data.

### 3.4l CONFIRMED, MAJOR MILESTONE — full extra-tile pipeline works end-to-end, no crash

Built and tested incrementally (construct → set `Index`/`LoadoutTemplate` → tile's own `Refresh()` → `AddChild` into `LoadoutList` → `SetHeightOverride` on the container). Final result, verified in-game: a real "Loadout 09 — Empty" tile renders correctly in the Loadouts screen, properly spaced (no overlap with "Last Gear State"), and even the hover tooltip ("RMB to save the current slot") works automatically. Right-click currently does nothing yet (not wired up — see open items below).

**Mod #1's rendering/layout problem is now fully solved.** Remaining work to turn this into a real feature:
1. **Generalize from one hardcoded tile (`Index = 8`) to a loop** creating tiles for every index from 8 up to the new `NumRecords - 1`.
2. **HAZARD, not yet fixed — duplicate-tile risk on repeat `Refresh` calls.** Our hook fires on *every* `Refresh` call, not just the first. If the Loadouts screen calls `Refresh` again on reopen (likely), reopening the screen repeatedly will keep adding more tiles (10th, 11th, ...) rather than stopping at the target count. Needs a guard — e.g. check `GetChildrenCount` against the desired count before adding, mirroring what the original (clamped) loop already does, rather than unconditionally adding one tile per hook fire.
3. **Interaction not yet wired up** — right-click (save) does nothing on the new tile. The tooltip alone works (likely driven by generic per-tile state, not the click delegate), but actually saving/loading a loadout into this slot needs the `OnClicked` delegate bound the same way the panel binds it for its normal 8 tiles (`K2Node_CreateDelegate_OutputDelegate_2` → `Widget_Loadout_C:OnClicked__DelegateSignature`, seen in the `Refresh` dump) — not yet attempted.

### 3.4m CONFIRMED — reopen bug fully fixed, tile persists across repeated screen opens

Retested with the `LoopAsync`-on-`panel` redesign (3.4k/l): full relaunch, one throwaway hot-reload, then opened the Loadouts screen three separate times in the same session. Log confirms a **fresh `Widget_LoadoutsPanel_C` instance is constructed every single time the screen opens** (three different object paths/instance IDs, each triggering its own `NotifyOnNewObject` firing) — confirming the earlier hypothesis that the panel doesn't persist across screen closes, unlike the outer Character menu. Each fresh instance correctly got its own extra tile added exactly once (the `GetChildrenCount` guard correctly saw `8` existing children each time, not an inflated stale count), with no duplicate stacking. "Loadout 09 — Empty" rendered correctly and persistently across all three opens, confirmed in-game via screenshot.

**Minor unexplained anomaly, not investigated further (no visible impact)**: in this test run, `LoadoutComponent #1`'s `GetMaxRecordsForTemplate` returned `0` both before and after the `NumRecords` patch, despite `NumRecords` correctly reading `20` — the first time this function hasn't simply mirrored `NumRecords` in every prior test. `LoadoutComponent #2` behaved normally (`11` → `20` after patch, as expected). Screen rendered correctly regardless, so whichever component actually drives the UI wasn't the anomalous one. Worth keeping an eye out for if `GetMaxRecordsForTemplate` behavior seems inconsistent again later.

**Mod #1 open items, unchanged**: (1) generalize from one hardcoded tile to a loop for however many extra slots the mod should ultimately support; (2) wire up `OnClicked` so the new tile(s) are actually interactive, not just visible.

### 3.4n CONFIRMED — why the manually-constructed tile ignored clicks: `ComponentDelegateBinding` requires the real `CreateWidget` lifecycle

Right-click (save) on the extra tile did nothing, while the hover tooltip worked. Tested calling `newTile:Construct()` manually after `StaticConstructObject` — **no effect**, right-click still dead. Root cause found in the `Widget_Loadout.json` FModel dump: the very first object in the export is a **`ComponentDelegateBinding`** owned by `Widget_Loadout_C` that wires the tile's internal `Button` widget (a `FocusButtonWidget`, part of the tile's own WidgetTree) to the tile's handlers:

- `Button.OnMouseRightClick` → `BndEvt..._0_OnFocusMouseEventDelegate...` (the save action)
- `Button.OnClicked` → `BndEvt..._2_OnAdvButtonClickedEvent...` (the load action)
- `Button.OnMouseEnter` / `Button.OnMouseLeave` → `BndEvt..._4` / `BndEvt..._3`

These "dynamic bindings" are applied by `UUserWidget::Initialize()` — a **native, non-reflected** function (not a UFunction, so not callable from Lua) that `CreateWidget` runs automatically and raw `StaticConstructObject` skips entirely. This cleanly explains the split behavior: the tooltip is a *pull-based* query (`GetValidInputActions` via `BPI_TooltipAction_Interface`, the engine asks the widget) so it worked with no bindings, while clicks are *push-based* delegates that were simply never bound. `Construct()` couldn't fix it because binding happens in `Initialize`, not `Construct`.

**Fix adopted (mirrors the game's own code path)**: construct the tile via `WidgetBlueprintLibrary.Create` — the native static function behind the Blueprint "Create Widget" node, which is literally what `Widget_LoadoutsPanel_C:Refresh`'s `Create` node calls. From Lua: `StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")` then `wbl:Create(panel, tileClass, playerController)` (world-context object, widget class, owning player from `FindFirstOf("PlayerController")`). This runs the full lifecycle: `Initialize` (delegate bindings), and `Construct` fires naturally when the widget enters the tree via `AddChild`. Fallback if this ever breaks: manually replicate the bindings from Lua with `newTile.Button.OnMouseRightClick:Add({ Object = newTile, FunctionName = FName("BndEvt__...") })` — documented but untested.

**Status: tested in-game — partial fix.** The `WidgetBlueprintLibrary.Create` tile renders correctly and the tooltip's RMB indicator now *lights up* on right-click (input reaches the tile's internal button — new behavior vs. `StaticConstructObject`), but the "SAVE LOADOUT?" confirmation dialog still doesn't appear.

### 3.4o CONFIRMED — the save/load dialogs are the PANEL's job; the panel subscribes to each tile's delegates, and nobody subscribed to ours

Traced via the panel's FModel JSON: the tile itself never calls any save function — no save/dialog-related calls anywhere in `Widget_Loadout.json`'s function locals. Instead, all the dialog machinery (`BeginDialog`, `Dialog_GenericWait_C`, `DialogResultDelegate`, `DeleteDialogResult`) lives in **`Widget_LoadoutsPanel_C`'s** graph. The panel's FuncMap has three tile-event handlers — `OnLoadoutClicked`, `OnLoadoutSlotSaved`, `OnLoadoutSlotDeleted` — and the panel's graph contains three `K2Node_CreateDelegate` locals typed to the tile's three delegate signatures (`OnClicked`, `OnLoadoutSaved`, `OnLoadoutSlotDeleted`), i.e. the panel's `Refresh` binds its handlers to every tile it creates. A tile's right-click handler just broadcasts a delegate; the panel's subscribed handler shows the confirmation dialog ("SAVE CURRENT CHARACTER LOADOUT TO SLOT N?" = Index+1) and performs the actual save on confirm. Our tile broadcast into the void because the panel never subscribed to it.

**Fix attempted and FAILED — hard UE4SS limitation confirmed in-game**: after creating the tile, tried replicating the three bindings from Lua via `newTile.OnClicked:Add({ Object = panel, FunctionName = FName("OnLoadoutClicked") })` etc. Result: `Error: [handle_unreal_property_value] Tried accessing unreal property without a registered handler. Property type 'MulticastInlineDelegateProperty' not supported.` — the installed UE4SS build cannot even *read* a multicast delegate property from Lua (the error fired on the `newTile.OnClicked` index lookup, before `:Add` was ever reached). Two additional lessons from the failure:
- **This error class pierces `pcall`**: despite the access being wrapped in `pcall`, the error aborted the entire enclosing callback — everything after it (tile `Refresh`, `AddChild`, final print) never ran, so the tile silently disappeared from the screen. Treat `[handle_unreal_property_value]` errors as callback-fatal, not catchable.
- The delegate-`:Add` syntax researched earlier evidently applies to a **newer/dev UE4SS** than what's installed — the current dev docs (`docs.ue4ss.com/dev/lua-api/classes/delegateproperty.html`) describe `DelegateProperty` (single-cast, assignable as a plain `{ Object = ..., FunctionName = ... }` table) and a `MulticastDelegateProperty` chapter with `Add`/`Remove`/`Clear`, but the installed build's property-handler registry clearly has no `MulticastInlineDelegateProperty` entry. A 2023 UE4SS discussion (`github.com/UE4SS-RE/RE-UE4SS/discussions/132`) confirms delegate support was a long-open feature request, with suggested workarounds being (a) hook the UFunctions that delegates eventually invoke, or (b) modify the Blueprint asset itself.

### 3.4p Workaround options for wiring the extra tile's interactions (decision pending)

1. **Hook the tile's own bound-event handlers + call the panel's handler directly** (stays in current architecture). The tile's `BndEvt..._0_OnFocusMouseEventDelegate...` (right-click) *does fire on our tile now* (tooltip RMB indicator lights up since the `WidgetBlueprintLibrary.Create` fix). A `RegisterHook` post-hook on that function fires for every tile; ours can be distinguished by identity — but that requires touching the hook's `self` param via the documented-but-never-tested `self:get()` accessor (`RemoteUnrealParam`). Prerequisite: a careful isolated `self:get()` safety test in ZZTestMod (crash risk is real but this is exactly what the scratchpad is for). If safe: on RMB-hook fire, `self:get()` → compare against our stored tile reference → if ours, call `panel:OnLoadoutSlotSaved(8)` directly (a plain BlueprintCallable-style UFunction call, a pattern proven safe many times).
2. **Upgrade UE4SS** to a newer build whose Lua API includes the `MulticastDelegateProperty` handler with `Add`. Unknown whether any released build actually has it (docs are the "dev" branch); would need changelog research + regression risk on everything already working.
3. **Abandon Lua widget injection for mod #1 and patch the Blueprint asset instead** (architecture change — user decision). Use UAssetGUI + the community `.usmap` to edit `Widget_LoadoutsPanel`'s compiled `Refresh` bytecode, changing the hardcoded clamp literal `8`, and ship as a `_P` patch pak. The panel would then create *all* tiles natively — delegate bindings, input, dialogs all just work, and the Lua mod shrinks to the `NumRecords` patch (plus maybe the SizeBox resize). This is also the workaround the UE4SS discussion itself suggests for delegate-bound Blueprints. Fits the user's hex-editing background; risk shifts from runtime crashes to asset-format fiddliness.

**Also observed again this run**: the `GetMaxRecordsForTemplate` returning `0` anomaly (3.4m) recurred, again on exactly one of the two `LoadoutComponent` instances (this time the one whose `NumRecords` already read 20 pre-patch — plausibly because both ZZTestMod and MoreLoadoutSlots now patch `NumRecords`, and the anomalous instance had already been patched by the other mod's hook). Still no visible in-game impact; still unexplained.

### 3.4q CONFIRMED — `self:get()` is safe; workaround option 1 chosen and implemented (pending test)

User chose option 1 from 3.4p. The ZZTestMod safety test (post-hook on `Widget_Loadout_C:BndEvt__..._4...` mouse-enter, granular step-by-step prints, 3 hover runs) **fully passed**: `self:get()` → non-nil, `:IsValid()` → true, `:GetFullName()` → correct tile instance path, `.Index` read → correct values. Bonus confirmation: run 2/3 was the mod's own created tile (`.Index = 8`), proving the class-level hook fires on our `WidgetBlueprintLibrary.Create`-made tiles and their identity/Index is readable from the hook. Also noteworthy from `GetFullName()`: `Create`-made tiles are outered to `BP_RemnantGameInstance_C` (the world-context chain), not to the panel — so identity matching must use the stored full-name registry, not Outer inspection.

**Implementation now in `MoreLoadoutSlots/Scripts/main.lua` (pending in-game test)**: post-hooks on the tile class's two click bound-event handlers — `BndEvt__..._0_OnFocusMouseEventDelegate...` (right-click) and `BndEvt__..._2_OnAdvButtonClickedEvent...` (left-click) — registered lazily on first tile creation (class guaranteed loaded then; a startup registration could fail with the class unloaded). Each hook: `self:get()` → match `GetFullName()` against a registry of tile names this mod created (so the game's own tiles are ignored — their clicks already reach the panel via their native delegate subscriptions, and forwarding those too would double-trigger dialogs) → read `.Index` → call `currentPanel:OnLoadoutSlotSaved(Index)` (right-click) or `currentPanel:OnLoadoutClicked(Index)` (left-click). All three panel handlers confirmed via the panel JSON to take a single int `Index` parm. `currentPanel` is a module-level variable refreshed on every `NotifyOnNewObject` panel construction, avoiding the stale-closure trap that caused the original reopen bug.

### 3.4r CONFIRMED, MAJOR MILESTONE — the 9th loadout slot is fully functional: renders, saves, and loads

In-game test of the click-forwarding implementation passed completely: right-click on the extra tile forwarded to `OnLoadoutSlotSaved(8)` and produced the real "SAVE LOADOUT?" confirmation dialog and a working save; left-click forwarded to `OnLoadoutClicked(8)` and loaded the saved loadout back. Both hooks registered cleanly (lazily, at first tile creation). Multiple screen reopens in the same session each got exactly one tile, as designed. **Mod #1's core mechanism is complete end-to-end**: `NumRecords` patch → `WidgetBlueprintLibrary.Create` tile → `Index`/`LoadoutTemplate` setup → tile `Refresh()` → `AddChild` → `SetHeightOverride` → click forwarding via `self:get()`-based hooks.

**Correction from further user testing — "fully functional" was premature.** Mouse save/load work, but three gaps remain on the extra tile: (a) **F-to-delete** does nothing; (b) **Space-to-equip** does nothing (both are keyboard context-actions, likely dispatched via `OnInputAction(ButtonWidget, InputAction: E_TooltipContextAction byte)` — the tooltip-framework function); (c) **missing equipped-slot save guard** — vanilla tiles disable right-click-save when their loadout is currently equipped, ours always shows the save prompt, confirming the guard lives tile-side (pre-broadcast) and our raw-click-event forwarding bypasses it. Safe gating signal identified without native-call guessing: `RefreshEquipped` (per its JSON locals) calls `GetLoadoutComponent` → `HasRecord`/`IsLoadoutEquipped` (native, on `/Script/Remnant.LoadoutComponent` — signatures unknown, do NOT guess-call) and drives the `EquippedIconBox` overlay's visibility from the result, so `tile.EquippedIconBox:IsVisible()` reads the equipped state safely. A ZZTestMod diagnostic (OnInputAction logger: tile Index, enum byte, equipped-icon visibility) is in place to establish whether `OnInputAction` fires on the mod's tile and which enum bytes mean delete/equip.

### 3.4s CONFIRMED — full input-to-code-path mapping for loadout tiles, via scripted three-path logging test

A ZZTestMod diagnostic hooked all three candidate paths simultaneously and the user pressed F/Space/RMB/LMB in scripted order on a vanilla tile and then the mod's tile. Result, unambiguous and identical for both tile kinds (all four paths fire on the mod-created tile too):

| Input | Path | Detail |
|---|---|---|
| F (delete) | `OnInputAction` only | `InputAction` enum byte = **3** |
| Space (equip) | `OnInputAction` only | `InputAction` enum byte = **1** |
| Right-click (save) | `Button.OnMouseRightClick` bound event (`BndEvt_0`) only | no `OnInputAction` involvement |
| Left-click (load) | `Button.OnClicked` bound event (`BndEvt_2`) only | no `OnInputAction` involvement |

(`E_TooltipContextAction` entry names not yet dumped — bytes 1/3 mapped behaviorally. The earlier "byte 1 fired right before RMB" confusion was just the user's Space press one second before right-clicking.)

**Implemented in `MoreLoadoutSlots` (pending test)**: (a) a third forwarding hook on `OnInputAction` — byte 1 → `panel:OnLoadoutClicked(Index)`, byte 3 → `panel:OnLoadoutSlotDeleted(Index)`, other bytes ignored; (b) the equipped-slot save guard — right-click forwarding is now suppressed when `tile.EquippedIconBox:IsVisible()` is true (the tile's `RefreshEquipped` keeps that icon in sync with the native `IsLoadoutEquipped`, so reading it avoids guess-calling a native function with unknown signature). Both open questions resolved by user testing, **no extra gating needed — the forwarding inherits vanilla behavior in both edge cases**: (a) vanilla DOES allow F-deleting the currently-equipped loadout (the slot just becomes empty, no gear change), and the mod's tile behaves identically; (b) F on an empty slot does nothing in vanilla, and the mod's tile likewise does nothing (the panel's `OnLoadoutSlotDeleted` handler evidently no-ops on empty slots).

### 3.4t DISPROVEN — the first-launch `NotifyOnNewObject` quirk is NOT registration-time class resolution

Controlled fresh-launch test (no hot-reload at any point): ZZTestMod polled `StaticFindObject` on the panel class — **not loaded** at mod startup and at the first (main-menu) `ClientRestart`, became **LOADED ~2s after startup** (before the real character spawn at +20s) — and registered a second, LATE `NotifyOnNewObject` at that moment. User then opened the Loadouts screen: **neither** the late registration nor MoreLoadoutSlots' startup registration fired. So delaying registration until the class is loaded does NOT fix the quirk; the class-resolution theory is dead. Next suspect: both registrations happened *before* the main-menu→world transition, while a hot-reload re-registers *after* it — something about that transition may break existing listener registrations in UE4SS v3.0.1. Not yet tested: registering `NotifyOnNewObject` fresh *after* the world transition (e.g. from a `ClientRestart`-triggered re-registration) without any hot-reload.

Side-findings from the same log: the installed UE4SS is **v3.0.1 Beta (Git d8189f3), circa early 2024** — relevant to both this quirk and the multicast-delegate limitation (3.4o), since newer builds may fix either. Also: **BPModLoaderMod is active** in the install (relevant if the Blueprint-asset-patch fallback in 3.4p is ever needed). Also: `ClientRestart` fires once at startup on the main menu (a player controller exists there) and again at each real spawn — harmless for the `NumRecords` patch, which just runs twice.

### 3.4u UE4SS UPGRADED to experimental-latest (v3.0.1-1009-gc2ac2464) — first-launch quirk FIXED

Upgraded from v3.0.1 Beta (d8189f3, the Nexus "Allow Asset Mods" bundle) to the official **experimental-latest** build. Motivations and outcomes:
- **First-launch `NotifyOnNewObject` quirk (3.4k/3.4t): FIXED.** Confirmed by cold-start test — the 9th tile appears on a fresh launch's first Loadouts-screen open, no hot-reload needed. The old shipping blocker is gone.
- **Multicast delegate Lua support (3.4o)**: the experimental changelog adds `Add`/`Remove`/`Clear`/`Broadcast` on multicast delegate properties — NOT yet re-tested in this project; the hook-forwarding design still works and stays for now. If verified later, the three forwarding hooks could be replaced by real delegate subscriptions (which would also inherit the vanilla tile-side gating natively).
- **New install layout**: everything lives in `Win64\ue4ss\` now (`UE4SS.dll`, `UE4SS-settings.ini`, `Mods\`, `UE4SS.log`), with only the `dwmapi.dll` proxy in `Win64\`. Mod registry: `mods.txt` is the only file to edit — `mods.json` is auto-regenerated from `mods.txt` at launch and hand edits to it are discarded (see 3.4aa). Symlink script updated accordingly (`scripts\New-ModSymlink.ps1` now defaults to the `ue4ss` subfolder).

### 3.4aa CONFIRMED — mod enable/disable: `enabled.txt` overrides everything; `mods.txt` is the only registry that matters; hand edits to `mods.json` are discarded

Found 2026-07-12 while trying to launch mod-free: setting both registry files to disabled did nothing — the mods still loaded.

- **`enabled.txt` (mere presence, contents irrelevant) force-enables a mod, bypassing the registry entirely.** It exists as UE4SS's zero-config drop-in path for end users. Since this project registers every mod in `mods.txt` anyway, the files were redundant and harmful — **removed from all mod folders 2026-07-12** (registry-only loading confirmed working by a clean launch). Don't add them to new mod folders.
- **`mods.txt` is the sole effective registry in current builds.** `mods.json` is the planned future replacement ([UE4SS PR #540](https://github.com/UE4SS-RE/RE-UE4SS/pull/540)), but during the transition `mods.txt` takes precedence and UE4SS *overwrites* `mods.json` from `mods.txt` at launch — user-confirmed empirically: disabling via `mods.txt` worked, disabling via `mods.json` was silently reverted. Register new mods in `mods.txt` only; never hand-edit `mods.json`. Precedence is slated to flip in some future UE4SS release — if registry edits ever stop working after a UE4SS upgrade, re-check which file wins.
- Enable/disable changes take effect on a full relaunch (hot-reload restarts already-enabled mods; it doesn't re-read enable state).
- **CRASH + resolution**: first boot after the upgrade crashed mid-UE4SS-init (log stopped right after the FName-constructor verification hook, no crash dump). Cause: **`AllowModsMod`** — the Nexus AMM package's C++ mod (`main.dll`, patches the game's mod-blocking delegate), built against the old build's ABI. Disabling it fixed boot entirely. Consequence: **asset/pak mods are currently not enabled** (irrelevant to our Lua mods; matters only if the Blueprint-asset-patch route or asset-based mods are pursued later — would need an AMM build compatible with experimental UE4SS, or a rebuilt equivalent).
- Settings ported: `ConsoleEnabled=1`, `GuiConsoleEnabled=1`, `GuiConsoleVisible=1` (new default is 0 — hidden; this is the purple tabbed GUI console with Live View), `GraphicsAPI=opengl`.
- **`EnableHotReloadSystem = 1`** — the new build makes Ctrl+R hot-reload an explicit `[General]` setting and the shipped ini had it OFF (that's why Ctrl+R silently stopped working post-upgrade; the GUI's "Restart All Mods" button was unaffected). `HotReloadKey = R`, Ctrl always required. Read at UE4SS init, so changes need a game relaunch.
- Rollback path: full old install preserved at `Win64\_ue4ss-3.0.1-backup` (restore its contents into `Win64` and delete `dwmapi.dll` + `ue4ss\`).
- Non-fatal boot warning under the new build: `Failed to find ConsoleManagerSingleton` (2 candidate addresses) — console functionality appears to work anyway; a custom AOB via `UE4SS_Signatures/ConsoleManager.lua` is the documented fix if console commands ever misbehave.

**Remaining work for mod #1 (none of it research-blocked anymore):**
1. ~~**Verify save persistence across a full game relaunch**~~ — **CONFIRMED**: a loadout saved to index 8 survived a full game relaunch. (High records 11-20 still need their own persistence test — see 3.4w.)
2. ~~**Generalize from 1 hardcoded extra tile to N**~~ — **DONE** at 20 total slots; ScrollBox injection (3.4v) solved the UI-space constraint, reserved-record discovery and gating fixes in 3.4w.
3. ~~**Shipping-blocker quirk**: `NotifyOnNewObject` doesn't fire on a fresh launch's first screen-open (3.4k)~~ — **RESOLVED by the UE4SS experimental-latest upgrade (3.4u)**; confirmed working on cold start with no hot-reload.
4. ~~Retire the ZZTestMod hover test~~ — done; ZZTestMod reset to an idle scratchpad (past diagnostics recoverable from git history).

### 3.4w 20 total slots WORKING — reserved record 10 discovered, empty-slot gating, FText property writes safe

Generalized from the single 9th tile to **20 total player slots** (user's chosen target), all interactions confirmed working. Three findings from the first 20-slot test round:

1. **Record index 10 is the game's "last gear state" auto-save.** A player-facing tile at `Index=10` self-overwrote on every equip — exactly the auto-save behavior of the character screen's last-gear-state tile. This finally explains native `NumRecords=11`: 8 visible slots + reserved storage, auto-save at the LAST native record (10). The auto-save stays pinned at 10 even with `NumRecords` patched to 21, so it's hardcoded, not "last record". **Mod behavior**: visible tiles skip record 10 (records used: 8, 9, 11..20; `NumRecords` patched to `TOTAL+1 = 21`), and skipped-past tiles get a `LabelOverride` so on-screen names stay a contiguous "Loadout 9".."Loadout 20".
2. **Empty-slot equip gating is also tile-side (pre-broadcast)** — like the equipped-save suppression (3.4s), vanilla blocks click/Space-equip on empty slots inside the tile's own handler, so raw forwarding bypassed it (our empty tiles were equippable). Fix: gate on the tile's own **`IsEmpty` bool property** (confirmed in the FModel dump as a class property on `Widget_Loadout_C`, kept in sync by its `Refresh`) — same read-cached-state-never-call-native pattern as `EquippedIconBox`. Confirmed working. F-delete needs no empty gate (the panel's delete handler checks `HasRecord` itself).
3. **FText PROPERTY WRITES work from Lua** with the mandatory `FText()` wrapper: `tile.LabelOverride = FText("Loadout 9")` renders correctly in-game, no crash. (The 3.4b hard crash was a raw Lua string into an FText *function parameter* — wrapped property writes are confirmed safe. Directly relevant to mod #2, LoadoutNamer, which needs exactly this kind of write.)

~~**Last open item**: persistence of the HIGH records (11-20) across a full relaunch.~~ **CONFIRMED**: "Loadout 20" (record 20, well beyond native storage) survived a full relaunch with correct contents. Mod #1 is functionally complete at 20 slots.

### 3.4x Multicast delegate Lua support CONFIRMED in experimental UE4SS — native subscriptions implemented with hook fallback

Stage-1 test (ZZTestMod, read-only): reading `tile.OnClicked` on a live vanilla tile now returns a `MulticastDelegateProperty` userdata exposing `Add`/`Remove`/`Clear`/`Broadcast` — the 3.0.1 behavior (unsupported-property error that pierced pcall and aborted the whole callback, 3.4o) is gone. API per the dev docs (docs.ue4ss.com/dev/lua-api/classes/multicastdelegateproperty.html): **`delegate:Add(targetUObject, FName("FunctionName"))`** — a UObject + function name, i.e. exactly the shape of the panel's own `K2Node_CreateDelegate` subscriptions. Lua closures cannot be bound, only reflected UFunctions.

Delegate/handler pairings verified from both FModel dumps: tile `OnClicked` → panel `OnLoadoutClicked`, tile `OnLoadoutSaved` → panel `OnLoadoutSlotSaved`, tile `OnLoadoutSlotDeleted` → panel `OnLoadoutSlotDeleted`.

**MoreLoadoutSlots now tries native subscriptions first, per tile**: `newTile.OnClicked:Add(panel, FName("OnLoadoutClicked"))` etc. On success the tile is fully vanilla — its own handlers gate the equipped/empty cases pre-broadcast, and all four inputs (LMB/RMB/Space/F) route through the three delegates natively, so none of the manual gating applies. On failure the bindings are rolled back (`:Remove` × 3, guarding against a half-bound tile double-firing) and the tile falls back to the proven hook-forwarding path (which stays in the code; the class hooks are only registered when at least one tile needs the fallback). The screen-open log line reports the per-path tile counts.

### 3.4y LoadoutNamer probes P1 + P2 both PASS — custom labels survive game refreshes; EditableTextBox injection fully works

First LoadoutNamer session (probes from `dev-docs/LOADOUT_NAMER_START.md` §7, run together in ZZTestMod; user-confirmed in-game 2026-07-12):

- **P1 — `LabelOverride` on a VANILLA tile is sticky.** Wrote `tile.LabelOverride = FText("P1 CUSTOM NAME")` on LoadoutList child 0 ("Loadout 1", record 0) + `tile:Refresh()`. The custom name rendered AND **survived equipping, deleting, and saving over that slot** — i.e. the game's own `Refresh`/`UpdateArchetypeText` passes do not clobber `LabelOverride`. Consequence: the namer only needs to apply names **once per screen-open** (same NotifyOnNewObject timing as mod #1); no event-driven re-apply hooks needed.
- **P2 — engine `/Script/UMG.EditableTextBox` injection works end-to-end.** Same recipe as the ScrollBox (3.4v): `StaticConstructObject(StaticFindObject("/Script/UMG.EditableTextBox"), panel.WidgetTree)` → `LoadoutList:AddChild(box)`. It renders, **takes mouse-click focus, and accepts keyboard typing while the Loadouts screen is open** (the game does not swallow the input). Typed text is readable from Lua via the **`Text` property** (`box.Text:ToString()`, polled at 500ms — every change logged correctly). Box became `:IsValid() == false` when the screen closed, so lifetime tracking via IsValid works.
- Probe-sequencing note: a probe that must run AFTER MoreLoadoutSlots' tile pass can just poll `LoadoutList:GetChildrenCount() >= 20` — no explicit inter-mod coordination needed.
- Still unproven for the namer input UX: commit detection (Enter → `OnTextCommitted` delegate vs. polling), pre-filling the box (`SetText` — a reflected function call with an FText arg, riskier class per 3.4b), positioning the box anywhere other than as a LoadoutList child, and gamepad interaction. (Most of these resolved in 3.4z.)

### 3.4z LoadoutNamer probe round 2 PASSES — F2-in-UI, hover hook, in-tile edit box all work; Option B (rename-in-place) fully viable

User-confirmed in-game 2026-07-12 (probe chained the whole flow: hover tile → F2 opens an EditableTextBox in the tile's title row → typing live-updates the label → F2 commits):

- **`RegisterKeyBind(Key.F2, fn)` fires while the Loadouts/Character UI has focus** — UE4SS keybinds reach Lua in menu context, including while an injected EditableTextBox holds keyboard focus (F2 committed mid-typing). This was the load-bearing unknown for keybind-driven UI mods; it works.
- **Hover tracking works**: `RegisterHook` on the tile's OnMouseEnter bound event (`Widget_Loadout_C:BndEvt__Widget_Loadout_Button_K2Node_ComponentBoundEvent_4_OnAdvButtonClickedEvent__DelegateSignature`; mapping confirmed in `dev-data/Widget_Loadout.json` lines 19–21, OnMouseLeave is `..._3_...`). `self:get()` → tile, read `tile.Index` — reliable per-tile hover identity.
- **The "Last Gear State" tile on the character screen is a `Widget_Loadout_C` with `Index=10`** — the reserved auto-save record renders as a hoverable tile there. Any rename/label feature must explicitly skip Index 10 (H7).
- **In-tile injection point**: `tile.Label` (named `TextBlock` variable, dump ~3550, font `GFGRemnantCracked_Font` size 12) → `GetParent()` = `HorizontalBox_202` → `AddChild(editBox)` puts the box in the title row. Squishes the row while the existing label text is present (long typed text also grows the box and pushes siblings) — blanking the label during the edit (`LabelOverride = FText(" ")` + `Refresh`, all proven ops) is the planned mitigation.
- **Live label updates work**: polling `box.Text:ToString()` at 250ms and writing `tile.LabelOverride` + `tile:Refresh()` on change updated the visible label in real time, no crash.
- **Custom labels persist across menu TAB switches** (same live tile instances) but not across menu close/reopen (tiles are reconstructed) — an apply-names pass per panel construction is the right persistence mechanism.
- **Enter/Escape focus quirks while the box has focus**: Escape defocuses the box (typing stops registering) and returns key control to the menu (Q/E tab-switching works again) but leaves the box widget alive; Enter also defocuses but does NOT return key control to the menu. Neither crashes. Consequence: a rename feature should own both keys via `RegisterKeyBind` (Enter = commit, Escape = cancel) and REMOVE the box in both cases, rather than leaving Slate half-focused.

### 3.4aa Tooltip title is writable + menu tab hotkeys (T/I/M) are gated on tab-button visibility

FModel dumps `Widget_LoadoutTooltip.json`, `Widget_InGameMenu.json`, `Widget_TabButton.json` (all in `dev-data/`, exported 2026-07-13) + ZZTestMod probe, all user-confirmed in-game:

- **Loadout tooltip title**: `Widget_LoadoutTooltip_C` (`/Game/UI2/UI_Widgets/UI_Game/UI_Game_Character/Widget_LoadoutTooltip`) has an `ItemLabel` TextBlock whose text is the static string `"Loadout"` (dump ~2186) — the game never varies it at runtime, so `ItemLabel:SetText(FText(...))` per hover is safe and writing the literal back restores the default. `FindAllOf("Widget_LoadoutTooltip_C")` + a ~1s 50ms rewrite poll from the hover hook lands reliably (LoadoutNamer ships this). Skip `Default__` objects — writing the CDO would leak into every future tooltip. The tooltip's action-prompt footer (Equip/Delete/…) is NOT in this Blueprint — parent class is native `FocusTooltipWidget` (`/Script/GunfireRuntime`), so the footer comes from elsewhere (unidentified).
- **Menu tab hotkey dispatch**: T/I/M call `Widget_InGameMenu_C:FocusTraits/FocusInventory/FocusMap` (hooks fire on every keypress; mouse clicks additionally fire the tab's `OnTabPressed` bound event first). The key→function mapping itself is native — `Widget_TabButton_C` (extends native `FocusWidget`) carries no hotkey data, nor does `Widget_InGameMenu`.
- **Hotkey suppression that WORKS**: the `Focus*` functions early-out on the target tab button's `IsVisible()` (they still fire when hidden, then do nothing). `SetVisibility(2)` (Hidden — keeps layout space, no tab-bar reflow, unlike Collapsed=1) on `menu.TraitTab/InventoryTab/MapTab` blocks the hotkeys. **`SetIsEnabled(false)` does NOT block them** (only affects mouse). The game resets tab visibility on menu reopen, so leaked Hidden state self-heals.
- **Counter-bounce is NOT viable**: every arrival at the character tab reconstructs the loadout panel (MoreLoadoutSlots re-injects, apply-names reruns — visible in logs on each tab return), so hooking `Focus*` and bouncing back would destroy an in-progress edit box. Tab switches rebuild the character panel; only same-tab persistence can be assumed.

### 3.4bb Widget styling from Lua — struct write-back rule, StaticFindObject path format, tooltip action-row injection (all user-confirmed in-game 2026-07-13)

Learned finishing LoadoutNamer's cosmetics (edit-box styling + tooltip "F2 Rename" prompt). All generalize beyond that mod:

- **Struct property writes need read-modify-WRITE-BACK.** Reading a struct property (`box.WidgetStyle`) hands back a detached copy; nested field writes mutate that copy invisibly. Pattern that works: read into a local, mutate (nested writes within the copy DO propagate, e.g. `style.BackgroundImageNormal.TintColor.SpecifiedColor.R`), then assign the whole struct back (`box.WidgetStyle = style`). Whole-struct assignment is supported and did not crash. Also pin `ColorUseRule = 0` (UseColor_Specified) on any `FSlateColor` you set. Styling before the widget enters the tree (`AddChild`) is the safe ordering.
- **`StaticFindObject` requires the FULL object path** (`Package.ObjectName`): `/Game/UI/Fonts/GFGRemnantCracked_Font.GFGRemnantCracked_Font` works; the bare package path fails with `GetPackageNameFromLongName: Name wasn't long`.
- **H4 re-confirmed on a layout property**: raw-writing `TextBlock.MinDesiredWidth` changes nothing on screen; the real `SetMinDesiredWidth()` setter works immediately. Raw writes are only for plain data, never anything Slate has to react to.
- **Fonts**: `FEditableTextBoxStyle` exposes the font at `WidgetStyle.TextStyle.Font` on this build (`.Font` directly does not exist); `FSlateFontInfo.Size` and `.FontObject` are writable. `UTextBlock.Font` same treatment via write-back.
- **Tooltip action-row injection** (the "F2 Rename" prompt): `Widget_Tooltip_Actions_C` (`/Game/UI2/UI_Widgets/UI_Game/UI_Game_Tooltips/Widget_Tooltip_Actions`, a named variable on tooltip widgets incl. `Widget_LoadoutTooltip_C`) has an **`ExtraActionList` HorizontalBox** — a purpose-built extension point. Create a `Widget_KeyIcon_C` (`/Game/UI/UI_Widgets/Widget_KeyIcon`) via `WidgetBlueprintLibrary.Create` + `GetOwningPlayer()`, write `keyIcon.KeyText:SetText(FText("F2"))`, `AddChild` it plus a styled TextBlock label — the badge renders in the game's native prompt style. `slot:SetVerticalAlignment(2)` (after AddChild) centers the label like the game's own. Its `InputActions` property is a TMap<E_TooltipContextAction, FText> rebuilt by `Build_List` — not needed for display-only entries.
- **Multiple tooltip instances can be alive at once** (hover B while A's tooltip lingers). Any injected-widget tracking must be per-instance (keyed by container `GetFullName()`, validating both liveness and still-parented-there) — a single global reference caused an alternating recreate loop that stacked duplicates.

### 3.4z CONFIRMED — multiplayer breaks `FindFirstOf("PlayerController")`; use `panel:GetOwningPlayer()` for CreateWidget

First co-op session with the mods active (2026-07-12, user playing with a friend): every extra-tile creation failed — `WidgetBlueprintLibrary.Create` returned a UObject that failed `IsValid()`, loop stopped at 0 tiles (scroll bar still appeared, since the ScrollBox splice needs no player controller). Cause: `FindFirstOf("PlayerController")` was passed as CreateWidget's owning player; in a multiplayer session more than one controller-like object can exist on the local machine, and CreateWidget handed a non-local controller returns an invalid widget. Classic UE multiplayer widget bug, not a UE4SS quirk.

- **Fix (user-confirmed working mid-session via hot-reload)**: ask the widget itself — `panel:GetOwningPlayer()` (standard `UUserWidget` reflected function, works on `Widget_LoadoutsPanel_C`) is guaranteed local. Old `FindFirstOf` kept only as a logged fallback. After the fix: 12/12 tiles, all-native delegate subscriptions, in the live co-op session.
- **Rule going forward**: any mod that calls CreateWidget or otherwise needs "the" PlayerController must get it from an owned widget (`GetOwningPlayer`) or otherwise verify locality — never `FindFirstOf`, which only worked solo by luck. Applies to LoadoutNamer and mod #3.
- **Still UNTESTED in multiplayer**: LoadoutComponent writes/saves. H2 (3.4c/3.4d — writes only proven safe with exactly one component instance) was established solo; a co-op session may hold multiple LoadoutComponent instances locally. The NumRecords patch ran without visible issues this session, but saving/equipping extra slots (9+) while in another player's game is unverified.

### 3.4v ScrollBox injection WORKS — runtime reparenting of live UMG widgets is viable

To fit more tiles than the panel's fixed height allows (the vanilla tree is `SizeBox_0` with a hard `HeightOverride=688` → `LoadoutList` VerticalBox, no scrolling anywhere), we splice a runtime-created engine `ScrollBox` between them: `SizeBox_0 → ScrollBox → LoadoutList`. **User-confirmed fully working on first attempt**: tiles render at normal size, mouse wheel scrolls, overflowed tiles are reachable, tooltips and all click/key interactions work on scrolled-to tiles.

Key points:
- **`StaticConstructObject` is fine for engine widgets.** `ScrollBox` is a raw C++ widget (`/Script/UMG.ScrollBox`), not a Blueprint UserWidget — it has no `Initialize()`-time `ComponentDelegateBinding` step to miss, which is exactly what made raw construction fail for the tile widget (3.4n). Constructed with outer = `panel.WidgetTree`.
- **Reparenting recipe** (game thread): grab `sizeBox = list.Slot.Parent` **before** detaching (after `RemoveChild`, `list.Slot` is gone), then `sizeBox:RemoveChild(list)` → `sizeBox:AddChild(scrollBox)` → `scrollBox:AddChild(list)`. All three worked live, mid-screen-display, with no visual glitch.
- **Desired-size sizing worked out**: inside a ScrollBox, children get their desired size instead of fill space — the concern that tiles might collapse to zero height did not materialize; tiles keep their native ~86px.
- The SizeBox stays at its native 688 (no more `SetHeightOverride` growth). NOTE: `list.Slot.Parent` now resolves to the **ScrollBox**, not the SizeBox — any future code reaching for the SizeBox must go one level further up.
- Two benign log artifacts each session: panel instances constructed during class-load / world transition never get a valid `LoadoutList` and time out the 40-attempt poll — these are not player-facing screens; the real screen-opens proceed normally.

### 3.4b HAZARD — calling a UFunction with an FText parameter via Lua crashed the game

Attempted `comp:SetDisplayNameForLoadout(slot.Template, 0, "ZZTestMod Custom Name")` (calling the confirmed-real `LoadoutComponent:SetDisplayNameForLoadout` function via Lua reflection, passing a plain Lua string for the `NewDisplayName` FText parameter) inside a `pcall`. **Result: hard game crash**, not a caught Lua error. `UE4SS.log` shows the last successful line was the property read just before this call — nothing was logged from inside or after the call, confirming the crash happened synchronously during the function invocation itself.

**Key lesson**: `pcall` only catches Lua-level errors. It does **not** protect against a native engine crash (e.g. bad memory access inside a C++/Blueprint-native function called via reflection) — those bypass Lua's error handling entirely and take the whole process down. This is a meaningfully different risk profile than the property reads/writes done so far (`comp.Slots`, `slot.NumRecords = 20`), which have all worked safely — **calling functions via Lua reflection, especially ones taking non-trivial parameter types like `FText`, is higher-risk than reading/writing properties directly**, and should be tested more cautiously (e.g. try a read-only function like `GetDisplayNameForLoadout` first, confirm calling functions on this class works at all, before attempting a write/mutating call).

**RESOLVED via web research** (UE4SS's own docs/GitHub issues, `docs.ue4ss.com/lua-api/global-functions/ftext.html` + `UE4SS-RE/RE-UE4SS` GitHub issues): this is a known UE4SS Lua issue, not specific to this mod or Remnant 2. Passing a plain Lua string directly where a function parameter expects `FText` causes UE4SS to misplace arguments on the call stack and attempt to write to the property through a null pointer — a hard native crash, exactly matching what we saw. **Fix**: UE4SS exposes a global `FText()` constructor in Lua specifically for this — wrap the string first:

```lua
local text = FText("My String")   -- correct
comp:SomeFunctionExpectingFText(text)

-- NOT this (crashes):
comp:SomeFunctionExpectingFText("My String")
```

Confirmed the read-only `GetDisplayNameForLoadout` call (object + int params only, no FText involved) works fine via direct Lua call — the crash really was isolated to the raw-string-into-FText-parameter case. Next retry of `SetDisplayNameForLoadout` should wrap the new name in `FText(...)` before passing it.

### 3.4c Retry with `FText()` wrapping — write succeeded, but crashed on the SECOND `LoadoutComponent` instance

Retried `comp:SetDisplayNameForLoadout(slot.Template, 0, FText("ZZTestMod Custom Name"))` with the fix from 3.4b applied. Result, per `UE4SS.log`:

- **First `LoadoutComponent` instance**: call succeeded — logged the confirmation, then a read-back via `GetDisplayNameForLoadout` correctly returned `"ZZTestMod Custom Name"`. **The FText fix works. Writing a custom loadout name via this API is confirmed functional.**
- **Second `LoadoutComponent` instance** (see `game_research.md`'s "exactly 2 instances" curiosity): the identical call — same function, same parameters — **crashed the game**, immediately after printing that instance's `Slot 1` read.

**Conclusion**: the crash was never really about `SetDisplayNameForLoadout` or FText marshaling being broken — those are confirmed working. It's specifically that **the second `LoadoutComponent` instance is unsafe to call mutating functions on** (reads are fine on both instances; only the first instance's write succeeded). Until the nature of this duplicate instance is understood, mod code doing any *write* through `LoadoutComponent` should target only the first found instance, not loop over `FindAllOf("LoadoutComponent")` blindly for mutating calls.

**Still unconfirmed**: whether the successful write on the first instance actually changed what's shown on the in-game loadout screen — the crash on the second instance happened before this could be visually checked. Needs a retry with the loop restricted to one instance, followed by an in-game visual check of "Loadout 01"'s displayed name.

### 3.4d Restricting the write to instance #1 fixed the immediate crash, but a NEW crash appeared on respawn

With the write restricted to `i == 1` only (3.4c's fix), the very first `ClientRestart` of the session (fresh game launch) completed cleanly: write succeeded, read-back confirmed `"ZZTestMod Custom Name"`, no crash. **But the in-game loadout screen still showed the unchanged original name** — checked properly this time (not a stale-UI false negative like the earlier `NumRecords` test).

Then, on the **next** `ClientRestart` in the same session (triggered either by hot-reloading mods + respawning, or simply by dying in-game) — **the game crashed again**, this time during the `SetDisplayNameForLoadout` call on what the log identified as instance #1 (crashed before printing the confirmation line). So "only instance #1 is safe" (3.4c's conclusion) is **not the full picture** — the crash is tied to something about calling this function more than once per session / across a respawn, not cleanly isolated to which instance it's called on.

**Working theory, unconfirmed**: on respawn, the previous character actor may linger briefly (pending destroy) while a new one spawns, and `FindAllOf`'s instance ordering/validity may not be reliable across that transition — instance "#1" on one call isn't necessarily the same *kind* of object as instance "#1" on the next. Would need a proper crash dump + symbols (WinDbg) to confirm; not pursued given the info we already have is enough to act safely.

**Practical fix applied, then refined**: first tried gating the write behind a one-time Lua flag (only fire on the first `ClientRestart` of a session). This still crashed after a hot-reload + respawn. Root cause identified: **the crash correlates with the number of live `LoadoutComponent` instances, not with call count**. A genuine fresh game launch (from the title screen, not a hot-reload) starts with exactly **1** instance, and the write is safe there. Every restart trigger after that point — hot-reloading mods and respawning, or simply dying in-game — shows **2** instances from then on, and the write crashes regardless of which instance (by `FindAllOf` order) is targeted. This makes sense once you consider that a mod hot-reload only resets the Lua VM, not the actual game world/actors — so "hot-reload + respawn" isn't a fresh game state the way a true relaunch is; the previous character actor apparently isn't fully gone.

**Practical implication for future testing/mods**: the write is only confirmed safe when `#FindAllOf("LoadoutComponent") == 1` — i.e. on a genuinely fresh game launch, before any hot-reload-triggered respawn or death has happened in that session. Guard added: skip the write entirely if more than 1 instance is found, rather than trying to guess which instance is safe. **This means testing this specific write requires a full game relaunch each time**, not just a hot-reload — a real cost to iteration speed worth remembering for this specific area of the game (loadout data), even though hot-reload works fine for everything else tested so far (the original `ClientRestart` hook test, all the read-only diagnostics).

### 3.4e CONCLUSION — confirmed: `SetDisplayNameForLoadout` does not affect the visible loadout screen text

Tested properly this time: full game relaunch (genuinely 1 `LoadoutComponent` instance, write fired and succeeded per log/read-back), then explicitly closed and reopened the Character > Loadouts screen. **"Loadout 01" still shows its original auto-generated name, unchanged.** This is now a clean result, not a stale-UI false negative.

**Mod #2 needs a different mechanism than `SetDisplayNameForLoadout`.** The function writes real, persisted data (`LoadoutRecord.DisplayName`) that the UI simply never reads. Best lead for what the UI *does* read: the earlier Live View dump of `Widget_Loadout_C` (the per-tile widget) showed a function `UpdateArchetypeText` containing a call to something named `CallFunc_GetArchetypeNameForCombo_ReturnValue` — strongly suggesting the on-screen names ("Dynamic Automator," "Shadow Assassin," etc.) are **procedurally generated from the pair of equipped archetypes**, via a lookup/combination table, not stored per-record free text at all. This reframes mod #2: rather than "expose an existing-but-hidden naming field," it likely needs either (a) a genuine UI text-override widget injected over/instead of the archetype-combo label (the harder, originally-assumed route), or (b) finding and hooking whatever function computes/returns the archetype-combo name and short-circuiting it with a custom stored string when one has been set. Worth inspecting `Widget_Loadout_C`'s `UpdateArchetypeText` function graph in FModel next, when picking mod #2 back up.

### 3.5 Live View GUI limitation (tooling note)

The UE4SS Live View / Object Explorer GUI, when you click into a property node under an object's `Class` branch, shows only **FProperty reflection metadata** (`ArrayDim`, `ElementSize`, `PropertyFlags`, `OffsetInternal`, etc.) — not the actual current value stored on a live instance. For reading real runtime values (array contents, current ints/strings/etc. on a specific live object), the reliable method confirmed working is: write a small Lua snippet (e.g. temporarily added to `ZZTestMod`) using `FindAllOf("<ClassName>")` to grab live instances, then read/print their properties directly, checked via `UE4SS.log`. Prefer this over screenshotting the Live View property panel — it won't have real values.

### 3.6 MOD #3 LEAD (major, scope-changing if it pans out) — the game ships a built-in inventory search filter widget, live but invisible

Found while grepping the existing Live View dump (`dev-data/WIdgetSearchResults.txt`, captured during the mod #1 tile investigation with the character menu open) for ring/amulet widget names — no new Live View session needed:

- **`Widget_InventorySearchFilter_C`** exists at `/Game/UI/UI_Inventory/Widget_InventorySearchFilter`. Its own WidgetTree contains **`SearchFilterText` (a real `EditableTextBox`)**, a `ComboBoxKey_58`, spacers/boxes — a complete search-filter UI.
- It is a **design-time child of `Widget_InventoryList_C`** (`/Game/UI/UI_Inventory/Widget_InventoryList`), which also has `InventoryGrid` + `PlaceHolderGrid` (both `WrapBox`) and `Widget_Inventory_Empty_ItemCard_C` placeholders.
- A **live instance chain existed at capture time** (dump line ~30950): `Widget_Character_C → Widget_Equipment_Screen_C → InventoryList → Widget_InventorySearchFilter → SearchFilterText`. So the filter widget is constructed and alive inside the real equipment screen — the player just never sees it (presumably collapsed/hidden; cut or unexposed feature).
- Related classes spotted: `Widget_InventorySearchContentItem_C`, `Widget_InventoryItem_C` (the item cards in the grid), `Widget_InventoryTab_C`.
- The equipment screen itself: **`Widget_Equipment_Screen_C`** at `/Game/UI2/UI_Widgets/UI_Game/UI_Game_Equipment/Widget_Equipment_Screen`, with named `Widget_EquipmentSlot_C` children `Ring1Slot`–`Ring4Slot`, `AmuletSlot` (dump lines ~16142–16156). Note the two UI roots: equipment screen under `/Game/UI2/...`, inventory list/filter under `/Game/UI/...`.

**Implication**: mod #3 ("search bar for rings/amulets") may be *un-hiding the game's own dormant search widget* rather than injecting a custom one — potentially far easier than assumed.

### 3.6a CONFIRMED from FModel dumps — the search filter is a complete, fully-wired feature, hidden only by an account-award visibility gate

All five widgets dumped to `dev-data/` (`Widget_InventorySearchFilter.json`, `Widget_InventoryList.json`, `Widget_Equipment_Screen.json`, `Widget_InventoryItem.json`, `Widget_InventorySearchContentItem.json`). Findings:

- **`Widget_InventorySearchFilter_C` is fully implemented, not a shell.** Its function list (~json line 1627-1741): `BuildFilterMap`, `GetAllFilterOptions`, `GetAllTagFilters`, `GetAllSearchItems`, `GetCurrentSearchIDs`, `TryBroadcastFilterChange`, `HasSearchFilterChanged`, `CacheLastSearchFilter`, `ClearAllFilters`/`ClearSearchText`/`ClearSearchTags`, `PopulateComboBox`, combo/text/button bound-event handlers, and three broadcast delegates: **`OnSearchFilterChanged`, `OnSearchFilterCommitted`, `OnSearchCleared`**. Text-changed AND text-committed events on `SearchFilterText` are both bound.
- **`Widget_InventoryList_C` consumes it.** Design-time delegate binding (json lines 51-53): the filter's `OnSearchFilterCommitted` → the list's `BndEvt__..._OnSearchFilterCommitted` handler. The list also has `GetQueryFilter`, `ShouldAddItem`, `ShouldHideItem`, `RefreshInventory`, `CurrentFilterTags` (Name property), and an `ItemTypesToShowFilter` array property (`Edit | BlueprintVisible`, array of `ItemType` classes) — likely what the combo-box categories draw from.
- **THE GATE (json line ~9474 + function at ~1330): the `Widget_InventorySearchFilter` child's `Visibility` property is *function-bound* to `Widget_InventoryList_C:CanSeeSearchBar`** — a BlueprintPure property binding, re-evaluated continuously. `CanSeeSearchBar`'s locals reveal its logic: `GetOwningPlayer` → cast to `RemnantPlayerController` (`/Script/Remnant`) → **`HasAccountAward(...)`** → Select between two `ESlateVisibility` values. I.e. the search bar renders only if the player has some account award that (evidently) is never granted — a shipped-but-disabled feature.

**Mod #3's likely shape (untested — next session's work)**: make `CanSeeSearchBar` return Visible. Candidate routes, in rough preference order: (a) `RegisterHook` post-hook on `CanSeeSearchBar` overriding the return value (UE4SS post-hooks can set out/return params — verify API for return-value override on a BlueprintPure `/Game/` function); (b) find which award FName/ID `HasAccountAward` checks (it's a literal in the ubergraph bytecode — try a live probe calling `RemnantPlayerController:HasAccountAward` with candidate names, or inspect further) and grant/spoof it; (c) sidestep the binding entirely by removing/replacing the property binding on the live widget. If the bar becomes visible, the filtering itself should Just Work — every event path and consumer handler already exists in the shipped Blueprints. Open question: whether `Widget_Equipment_Screen`'s ring/amulet list context populates the filter's combo/tags sensibly, and whether gamepad focus navigation handles the bar.

### 3.6b RUNTIME-CONFIRMED (2026-07-13 session, ZZTestMod probe rounds 1–3) — the shipped filter is a keyword→tag prototype, NOT name/description search

Supersedes 3.6a's "filtering should Just Work" hope. All confirmed against live `UE4SS.log`:

- **The visibility gate is inert at runtime.** `CanSeeSearchBar` fires only ~5 times during `Widget_InventoryList_C` construction, then never again. A plain `SetVisibility(0)` on the live `Widget_InventorySearchFilter` **sticks** — no per-frame stomping. No hook/award spoof needed to show the bar. It re-hides only when the whole character screen is reconstructed (screen close/reopen), so a feature mod re-applies visibility per construction.
- **Two layers of hiding**: the gate binding on the filter child, *plus* `SearchFilterText` (the actual text box) defaults to `ESlateVisibility::Collapsed` at the asset level (`Widget_InventorySearchFilter.json` line ~148). Unhide both.
- **One live filter instance** serves every equipment tab (rings, amulet, armor, relic, weapons) under `Widget_Character_C → Widget_Equipment_Screen_C → InventoryList`. `FindAllOf` also returns the class widget-tree template (outer path starts `/Game/...` instead of `/Engine/Transient...`; its `SearchFilterText` is invalid) — skip it.
- **Hook registration on `/Game/` classes fails at mod-start on a fresh launch** ("no UFunction with the specified name was found") because the Blueprint isn't loaded yet; it succeeds once an instance has existed. Feature mods must defer registration (e.g. `NotifyOnNewObject`).
- **Why typing doesn't filter** (traced with log-only hooks on the whole chain): per-keystroke `TextChanged` fires but leads nowhere (no consumer of `OnSearchFilterChanged`). Enter fires `TextCommitted → GetAllSearchItems → TryBroadcastFilterChange`, but the list's `OnSearchFilterCommitted` handler never fires — `HasSearchFilterChanged` finds no change because typed text is matched against **`FilterMap`**, built by `BuildFilterMap` (fires once at construction) from **`DataTable_ItemFilters`** (`/Game/UI/UI_Inventory/DataTable_ItemFilters`, rows = FName → `ItemFilterRowData` from `/Script/GunfireRuntime`). The shipped table evidently contains only dev-test rows — exactly the combo box's leftover options ("Fire", "Fire Rate", "Bleed"; `PopulateComboBox` fills the combo from the FilterMap keys). Matches become `CurrentSearchIDs` → tags (`GetAllTagFilters`) → the list filters by tags, same machinery as the W-filters menu. **It was never an item-name/description search.**
- The filter's own internals do work: X button clears the box; `OnSearchFilterCommitted`/`OnSearchCleared` delegates carry **no parameters** (consumers pull state via `GetQueryFilter`/`GetCurrentSearchIDs`).
- **The list-side extension point for mod #3's real implementation**: `Widget_InventoryList_C:ShouldHideItem(ItemID: int, Inventory: InventoryComponent) → Out: bool` (`Widget_InventoryList.json` ~6453) — fires per item on every grid refresh; `RefreshInventory` is BlueprintCallable to re-trigger filtering. Planned hybrid: keep the game's bar UI (unhidden), hook `ShouldHideItem` to do our own name+description matching, call `RefreshInventory` on text change. Open research: getting name/description text per `ItemID` (via `InventoryComponent` or the item widget); contents of `DataTable_ItemFilters` (FModel export requested).

### 3.4-old Open sub-questions after this pass (superseded in part by 3.4 above)
- Is the loadout slot count a property on some default object (easy `SetPropertyValue` patch, per 3.2's pattern) or is it baked into the widget's layout graph (needs the heavier Blueprint/widget-editing route from the Dmgvol guide, section 2)? — **Answer needed from Live View inspection, not guessable from docs.**
- For the search bar / loadout naming: `NotifyOnNewObject` on the relevant widget class is clearly the right entry point (per 3.1) — but we still need the actual widget class path, which only Live View or the Discord can give us.
- The R2-specific `Rem2Proj` GitHub repo (by AuriCrystal) is a pre-configured UE 5.2 project specifically set up for Remnant 2 asset cooking (handles the IOStore/chunk-assignment settings from the Dmgvol guide automatically) — worth using directly instead of hand-configuring a fresh UE project, if/when we need the full asset-pipeline route.

---

## 4. Dev Environment Setup

### 4.0 Starting inventory (as of this session)
Already installed: FModel, HxD/Hex Editor Neo, UAssetGUI, Unreal Engine 5.2. Believed installed: Remnant 2 "Allow Assets Mod" (AAM) and UE4SS (likely whatever version AAM bundled at download time).

### 4.1 Critical gotcha: AAM's bundled UE4SS is known to go stale
Community consensus (posts as recent as June 2026) is that the AAM zip's bundled UE4SS build regularly falls behind the game's current patch, causing summon commands / mods to silently stop working even though the console still opens. **Fix used by the community**: manually download the latest **non-experimental, non-dev, non-experimental-latest** release from `github.com/UE4SS-RE/RE-UE4SS/releases`, and replace ONLY two files in the flat `Win64` folder — `UE4SS.dll` and `dwmapi.dll` — leaving everything else from AAM (settings, Mods folder, other DLLs) untouched.
- **Do NOT** switch to the newer `ue4ss/` subfolder layout (introduced in UE4SS 4.0+) for Remnant 2 — AAM and the existing R2 mod ecosystem all still expect the legacy flat layout (`Win64\Mods\`, `Win64\UE4SS-settings.ini`, `Win64\UE4SS.dll`, `Win64\dwmapi.dll` all directly in the same folder as `Remnant2-Win64-Shipping.exe`). UE4SS maintains backward compatibility with this legacy location, so this is a supported combination, not a hack — just don't "upgrade" the folder layout on your own.

### 4.2 Setup checklist (in order)

1. **Locate the right folder.** `Steam\steamapps\common\Remnant2\Remnant2\Binaries\Win64\` — this is the folder that contains `Remnant2-Win64-Shipping.exe` (the *actual* large executable, not a launcher wrapper). Everything UE4SS/AAM-related goes here, flat, no subfolder.
2. **Verify/update UE4SS to latest stable.** Download the latest tagged release (not `experimental-latest`, not a `zDEV` build unless doing C++ mod dev) from `github.com/UE4SS-RE/RE-UE4SS/releases`. Replace `UE4SS.dll` and `dwmapi.dll` in the Win64 folder with the ones from that zip. Leave `UE4SS-settings.ini` and the `Mods` folder from AAM as-is (don't overwrite `UE4SS-settings.ini` unless troubleshooting, since AAM's version and the new one may have different keys).
3. **Confirm AAM's own components are present**: console enabler + blueprint mod loader. These should already be in the `Mods` folder from AAM's own install — check `Win64\Mods\mods.txt` and confirm the relevant lines aren't set to 0 (per AAM's own instructions from earlier research).
4. **Enable the debug GUI / Live View** — edit `UE4SS-settings.ini` in the Win64 folder:
   ```ini
   [Debug]
   ConsoleEnabled = 1
   GuiConsoleEnabled = 1
   GuiConsoleVisible = 1
   ```
   If the GUI opens blank/white, switch `GraphicsAPI` to `dx11` in the same file (OpenGL is default in current releases and occasionally has compatibility issues).
5. **Launch the game once, get to the main menu, close it.** This lets UE4SS generate its first-run files/log. Confirm `UE4SS.log` exists in the Win64 folder with a fresh timestamp and no fatal errors — this is the standard "did it actually load" check.
6. **Launch again, open the debug console** (default key is F10, or the new Tilde key added in recent releases) and confirm the Live View / debug GUI actually renders. This is the tool we'll use to browse the live widget/object tree for the loadout screen and inventory screen later (see section 3.3).
7. **Get the community FModel mapping file.** Join the modding Discord (`discord.gg/jX5qd2RefK`) and grab the pinned/linked Remnant 2 `.usmap` mapping file (referenced in the "Modding 101" README from section 3.2 — it's posted in a specific Discord channel/message, not hosted on a plain download link, so this has to be a manual Discord step). Point FModel at the Remnant 2 `Paks` folder and load the mapping file so class/property names resolve instead of showing as hashes.
8. **(Later, only if pursuing the full .pak/blueprint-asset route)** Clone AuriCrystal's `Rem2Proj` GitHub repo into your UE 5.2 Projects folder — it's a pre-configured Remnant2-named UE project with chunk-assignment/IOStore packaging settings already set up correctly, saving the manual "name your project exactly like the game, enable chunk IDs, disable shared material shader code" setup from the generic Dmgvol guide (section 2).

### 4.3 Verification / sanity checks before writing any real mod code
- `UE4SS.log` shows no fatal errors on launch.
- Debug console opens in-game (F10 or Tilde).
- Live View window renders and lets you browse live objects (test: search for `PlayerController` and confirm you see a live instance with real property values).
- A trivial test Lua mod (e.g. a `print()` on `ClientRestart`, the same hook everyone uses per section 3.1) shows output in the UE4SS console — confirms mods are actually loading and the hook mechanism works end-to-end before building anything real.
- FModel opens the Remnant 2 Paks folder without errors and resolves names correctly once the mapping file is loaded (test: browse to a known path like `/Game/World_Nerud/Items/Trinkets/Amulets/` from section 3.2 and confirm it's readable, not hashed garbage).

### 4.5 Environment verification — CONFIRMED WORKING (as of this session)

Actual installed environment turned out healthier than initially assumed — no DLL staleness issue found:

- **UE4SS version**: v3.0.1 Beta #0 (Git SHA #d8189f3), correctly detected `EngineVersion: 5.2`, all required memory signatures found cleanly on scan (no AOB failures).
- **Layout**: confirmed flat legacy layout in `Win64\` (not the newer `ue4ss\` subfolder convention) — correct for this AAM-based setup.
- **mods.txt / Mods folder**: `BPML_GenericFunctions`, `BPModLoaderMod`, `CheatManagerEnablerMod`, `ConsoleCommandsMod`, `ConsoleEnablerMod`, `AllowModsMod`, `Keybinds` all enabled and started without errors; `ActorDumperMod`, `SplitScreenMod`, `LineTraceMod`, `jsbLuaProfilerMod` present but intentionally disabled.
- **Debug GUI / Live View**: already enabled (`GuiConsoleEnabled`/`GuiConsoleVisible` = 1 confirmed by user), `imgui` config present from prior use.
- **End-to-end mod test**: wrote and ran a minimal test mod —
  ```lua
  print("[ZZTestMod] Loaded and running.\n")
  RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(self, NewPawn)
    print("[ZZTestMod] ClientRestart fired - hook is working.\n")
  end)
  ```
  placed at `Mods\ZZTestMod\Scripts\main.lua` + `enabled.txt`, registered in `mods.txt`. **Confirmed working**: both print statements appeared in the UE4SS console on mod load and character spawn respectively. This validates the full chain — mod loading, `RegisterHook`, and the `ClientRestart` bootstrap hook used throughout section 3's examples — before any real widget/loadout work begins.
- **Cleanup note**: an earlier stray Blueprint mod reference (`MyMod_P` / `/Game/Mods/MyMod_P/ModActor`) that was logging a harmless "ModClass is not valid" warning has been resolved — the underlying `.pak`/`.ucas`/`.utoc` files under `Remnant2/Content/Paks/LogicMods` were located and deleted (leftover from an earlier hex-editing experiment, contents/purpose no longer known/needed).

**Remaining before real mod work**: get the community `.usmap` mapping file for FModel from the modding Discord (section 4.2 step 7) — not yet done as of this session. Everything else in the setup checklist is now verified complete.

---

## 5. Open Questions / Risks

- Multiplayer/anti-cheat implications of DLL-injection mods (UE4SS) vs. pure pak/config mods — need to confirm current stance before publishing anything, especially for widget-injection mods which are more invasive than value tweaks.
- Whether loadout slot count is stored in a simple property (easy `SetPropertyValue` patch per section 3.2) vs. hardcoded array size + hardcoded UI slot count (harder, requires both blueprint and widget changes) — cannot be resolved from docs; needs Live View / FModel inspection of the actual loadout screen (see 3.3).
- Need to find/generate an SDK dump (via UE4SS's SDK generator) specific to the installed Remnant 2 version before any hooking work can start — class names won't be guessable from a generic guide. Same applies to the specific widget class names for the loadout screen and inventory screen — need Live View or the modding Discord (`discord.gg/jX5qd2RefK`) plus the community `.usmap` mapping file for FModel.
- Not yet confirmed: does `NotifyOnNewObject` reliably fire for UMG widget classes specifically (as opposed to Actor/Component classes, which is what most documented examples use)? Worth testing early/small before building either UI mod around it.
