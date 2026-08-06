# PrismLegendaryReroller — mod reference

Status: **feature-complete and user-confirmed** as of 2026-08-04. Source: `PrismLegendaryReroller/Scripts/main.lua`. This doc is the what/why of this mod specifically; the engine/UE4SS research behind it lives in `docs/remnant2-modding-research.md` §3.20.

## What it does

- Prisms cap at level 51, at which point a legendary (Mythic) bonus is rolled from a pool. Rerolling that bonus normally requires "cleansing" it — which drops the Prism back to level 50 and forces a relevel before you're allowed to roll again, on top of the grind to reach 51 in the first place.
- This mod removes that penalty. When a legendary-only cleanse fires (`APrismStone::ServerFlushSegment`), if the Prism was at level 51 immediately beforehand, the mod grants back exactly enough experience (via the game's own `AddExperience`) to relevel it to 51 right after the flush completes — so the next roll is available immediately.
- **The whole-Prism cleanse is untouched on purpose.** That's a separate action (`ServerFlushPrismStone`) that resets everything — level to 0, every rolled stat segment cleared — not just the legendary bonus. This mod never hooks or affects it.

## User guide

No keybinds, no UI. Play normally:

1. Level a Prism to 51 and let it roll a legendary bonus, same as vanilla.
2. Cleanse the legendary bonus (not the whole Prism) the same way you always would.
3. The Prism is back at level 51 immediately — go ahead and reroll again right away, no relevel needed.

`UE4SS.log` prints `[PrismLegendaryReroller] Legendary cleanse detected - restored level 51 (AddExperience <amount>).` each time this fires, if you want to confirm it's working.

## Key implementation facts

- Hooks the **native** function `/Script/Remnant.PrismStone:ServerFlushSegment(SegmentIndex, NumRefundLevels)`, registered at **top level** (not nested inside a `ClientRestart` hook, unlike this project's other mods) — `APrismStone` is a native engine class, so its UFunctions are already resident at script-load time; nesting inside `ClientRestart` was tried first and never fired on a hot-reload, since that event had already happened earlier in the play session.
- Detection signal: `GetPrismStoneLevel() == 51`, read **synchronously inside the pre-hook**, before the real flush runs (native `/Script/` paths are pre-hooks). A Mythic segment can only exist on a Prism that has already reached 51, so this reliably distinguishes a legendary-bonus cleanse from a regular (non-Mythic) segment reroll, which also goes through `ServerFlushSegment` but at any level, with a real `NumRefundLevels` cost — no need to inspect the segment's row name or category at all.
- `PrismStoneLevel` has no backing save field — `UPrismStoneInstanceData` stores `CurrentSegments`/`CurrentSeed`/`PendingExperience`/etc., never a raw level int. The vanilla 51→50 drop on a legendary cleanse is a side effect of the Mythic segment's removal (it appears to carry exactly 1 level's worth), not something the game explicitly sets — confirmed by observing `ServerFlushSegment` always pass `NumRefundLevels=0` for a legendary flush, yet the level still drops. This is why the fix works by *restoring* the level afterward through `AddExperience`, rather than trying to suppress a parameter that doesn't control the behavior.
- The relevel call (`GetExperienceRequiredForLevel(51)` + `AddExperience`) is deferred via `ExecuteInGameThread`, keeping the hook body itself to safe reads only (`self:get()` + one no-arg getter call).
- Scoped strictly to the object the game itself calls `ServerFlushSegment` on (`self`) — never touches any other Prism you own, even ones with live in-memory instances from Inventory/UI browsing.

## Known warts / deliberate scope cuts

- Only tested on UE4SS experimental-latest.
- The `NumRefundLevels` parameter on a regular (non-Mythic) segment reroll is left completely alone — that grind is intentional game balance the user didn't ask to change.
- Hook path (`/Script/Remnant.PrismStone:...`) was reverse-engineered from the `CXXHeaderDump` UE4SS generates from the live binary (`<game>/Binaries/Win64/ue4ss/CXXHeaderDump/*.hpp`), not from an FModel export — no Prism-related FModel dump exists in `dev-data/` for this project. If a future game patch renames/moves this function, re-grep that directory for `prism` (research doc §3.20 has the full lookup trail).
