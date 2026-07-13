# CLAUDE.md

## What this project is

UE4SS Lua mods for Remnant 2 (Steam/PC, Unreal Engine 5.2). Three mods, in priority order: increase loadout slot count (**DONE** — `MoreLoadoutSlots`, 20 slots), name loadout slots, add a search bar to the ring/amulet inventory screen. Session docs live in `dev-docs/`, research in `docs/` — they are the source of truth, not this file.

## Project owner

Beginner modder — some hex-editing and light Blueprint-modding background, no prior UE4SS/Lua modding experience. Explain non-obvious UE/UE4SS concepts when they come up rather than assuming familiarity. Flag architecture/priority decisions back to the user instead of deciding unilaterally — this repo is implementation; planning happens in a separate conversation.

## Where things are

- `dev-docs/` — session handoff briefs. `LOADOUT_NAMER_START.md` is the entry point for mod #2 work; `START_HERE.md` is the original project handoff (partially stale — the per-mod briefs and research doc supersede it where they conflict).
- `docs/remnant2-modding-research.md` — all research to date: toolchain, confirmed UE4SS Lua API patterns, hazards, open questions. Check the relevant sections before writing new hooks or investigating widgets, so findings (and crashes) aren't rediscovered from scratch. `docs/game_research.md` mirrors game-side findings/milestones.
- `dev-data/` — FModel property-JSON dumps of game widgets (`Widget_Loadout.json`, `Widget_LoadoutsPanel.json`). This is where confirmed class/property/function names come from — grep these before considering Live View.
- `<ModName>/enabled.txt` + `<ModName>/Scripts/main.lua` — each mod's actual source, one folder per mod (`MoreLoadoutSlots` done; `LoadoutNamer`, `RingAmuletSearch` planned).
- `ZZTestMod/Scripts/main.lua` — the diagnostics scratchpad. Throwaway probes go here, never in feature mods. When a probe is done, reset this to idle and note what it proved in its header comment (past probes stay recoverable from git history).
- Live game folder: `...\Remnant2\Remnant2\Binaries\Win64\ue4ss\` (UE4SS experimental-latest layout — only the `dwmapi.dll` proxy sits in `Win64\` itself). `UE4SS.log` lives here (read this to verify anything, don't assume Lua is correct from inspection alone), and `Mods\` contains BOTH registry files, `mods.txt` and `mods.json` — keep them in sync; register every new mod in both. Old 3.0.1 install preserved at `Win64\_ue4ss-3.0.1-backup` for rollback.

## How mod folders get to the game

Each mod folder in this repo is symlinked into the game's `Win64\ue4ss\Mods\` folder via `scripts\New-ModSymlink.ps1` (run elevated; instructions in `START_HERE.md`). This is a one-time setup per new mod folder, not a recurring step. Never copy files into the game folder manually — if a mod folder isn't showing up in-game, check whether the symlink exists before copying anything.

## Development workflow

- Test incrementally against the real `UE4SS.log`, not just by reading the Lua. Write the smallest change that tests one thing, have the user launch/hot-reload, then read the log output back before continuing.
- When the user tests, ask for **behavioral observations**, not just pass/fail — the user's in-game observations (a slot silently self-overwriting, empty slots behaving differently on mod tiles vs. vanilla) caught bugs the logs alone never would have. Their theories about game behavior have a good track record; take them seriously as leads.
- **Respect the risk ladder.** Property reads/writes via reflection are the safest operation; calling reflected functions is riskier (argument marshaling can hard-crash); struct-typed arguments are the riskiest. Before calling a mutating reflected function, probe a read-only one on the same class first. Always wrap strings destined for FText/FName params in `FText(...)`/`FName(...)`. A `UE4SS.log` that just stops mid-line means a **native crash** — `pcall` cannot catch these, so smallest-change-per-reload is the only real protection. Full hazard list: research doc §3.4 (FText, `self:get()`, layout setters vs. raw writes, LoadoutComponent write safety).
- **Prefer the game's own machinery over reimplementing it.** Subscribing mod-created widgets to the game's delegates (`delegate:Add(uobject, FName("Handler"))`), constructing real engine widgets (`StaticConstructObject`), and using the game's own Blueprint classes as templates all inherit vanilla behavior for free (gating, tooltips, focus). Manual hook-forwarding that re-creates game logic in Lua is the fallback, not the first choice — every game behavior manually re-created is a behavior that can silently drift from vanilla (this is exactly how the empty-slot bug happened).
- Hot-reload (`Ctrl+R` in-game, or the GUI console's reload button) restarts all mods without a full relaunch — prefer this over asking for a full relaunch when iterating. (Exception: `UE4SS-settings.ini` changes and anything the research doc flags as requiring a fresh world state need a full relaunch.)
- **Treat test-loop friction as a first-class bug.** Broken hot-reload went undiagnosed for a while as a "minor annoyance" and taxed every iteration until fixed (it was one ini setting). If launching, reloading, or reading logs gets slower or flakier, stop and fix that before continuing feature work.
- Widget class names, property names, and array structures for Remnant 2 cannot be guessed or inferred from generic UE documentation — they must come from the `dev-data/` FModel dumps or live inspection (UE4SS Live View). Do not invent or assume a class path; if it's not already confirmed in the research doc or a dump, that's a research step to do first, not a detail to guess at.

## Finding game internals — use the lookup ladder in this order

1. **Grep the `dev-data/` FModel dumps first.** Instant, offline, exact — property names, types, flags, delegate signatures, function lists. When a new widget/class becomes a target, the first move is to have the user export its property-JSON from FModel into `dev-data/` once; that dump then answers most questions for the rest of the mod. Caveats: dumps are *compiled* reflection output (`CallFunc_X_ReturnValue` temp names, not visual graphs) — logic-flow readings from them are inference, weight them lower than a plain property name; and dumps go stale when the game patches — treat line numbers cited in docs as approximate anchors and re-dump after game updates.
2. **Live View only for live-instance questions** — how many instances exist, the actual runtime hierarchy, whether an object is currently alive. Keep searches narrow with *Instances only* checked and *Include CDOs* unchecked (a broad search once produced a 10.8MB result file usable only via grep). The property panel shows FProperty *metadata*, not live values — don't screenshot it expecting values.
3. **ZZTestMod Lua probe + `UE4SS.log`** for actual runtime values. This is the only reliable way to read what's really in memory, and it doubles as proof the access pattern is safe before feature code uses it.

When a lookup succeeds, record the confirmed name (and dump line number) in the research doc or the relevant handoff brief immediately — cited names are what make the next lookup a grep instead of a research step.
- Only read the specific research doc sections and code relevant to the current task — don't re-read the entire research doc or reload unrelated mod folders' code into context for a focused change.
- When a finding changes the difficulty or approach of a mod (e.g. something turns out to be layout-graph-bound instead of a simple property patch), update `docs/remnant2-modding-research.md` and flag it to the user clearly — this may change scope or priority.
- **Beware false negatives.** Twice this project, "the patch did nothing" turned out to be a stale-UI/timing artifact, not a wrong hypothesis (the UI had already rendered before the write). Before concluding something is hardcoded or impossible, verify the change was actually in place *before* the reading code ran — reproduce from a fresh screen-open or relaunch.
- **Never let a pcall swallow an error silently on a novel operation.** A broad pcall around a styling block hid a trivial path-format bug for ~4 reload cycles; splitting it into per-write pcalls that print the error message solved it in one reload. Corollary: a status log that says "ok" only means Lua accepted the write — visual/layout effect must be confirmed by the user's screenshot or observation (a raw write to a layout property logs "ok" and does nothing; H4).
- This is genuinely novel territory for Remnant 2 (no public precedent for in-game widget-injection mods on this game) — document findings as you go, even ones from failed approaches, since there's no existing mod to fall back on for reference.
- When a mod is completed (or a session's work wraps a major phase), write a handoff brief in `dev-docs/` for the next session (`LOADOUT_NAMER_START.md` is the model): proven building blocks, hazards, confirmed names/paths, open design questions for the user. The next session reads that brief first, not the whole research doc.
