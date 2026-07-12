# CLAUDE.md

## What this project is

UE4SS Lua mods for Remnant 2 (Steam/PC, Unreal Engine 5.2). Three mods, in priority order: increase loadout slot count, name loadout slots, add a search bar to the ring/amulet inventory screen. See `START_HERE.md` for current status and next steps, and `remnant2-modding-research.md` for all research/findings. Read both before starting work each session — they are the source of truth, not this file.

## Project owner

Beginner modder — some hex-editing and light Blueprint-modding background, no prior UE4SS/Lua modding experience. Explain non-obvious UE/UE4SS concepts when they come up rather than assuming familiarity. Flag architecture/priority decisions back to the user instead of deciding unilaterally — this repo is implementation; planning happens in a separate conversation.

## Where things are

- `START_HERE.md` — current status, immediate next steps, symlink setup instructions. Read first.
- `remnant2-modding-research.md` — all research to date: toolchain, confirmed UE4SS Lua API patterns, real Remnant 2 asset path conventions, open questions. Read before writing new hooks or investigating widgets, so findings aren't rediscovered from scratch.
- `<ModName>/enabled.txt` + `<ModName>/Scripts/main.lua` — each mod's actual source, one folder per mod (`LoadoutSlotCount`, `LoadoutNamer`, `RingAmuletSearch`).
- Live game folder: `...\Remnant2\Remnant2\Binaries\Win64\` — this is where `UE4SS.log` lives (read this to verify anything, don't assume Lua is correct from inspection alone) and where `Mods\mods.txt` lives (shared registry file, edited directly, not part of any mod's symlinked folder — add a line here for every new mod).

## How mod folders get to the game

Each mod folder in this repo is symlinked into the game's `Win64\Mods\` folder (instructions in `START_HERE.md`). This is a one-time setup per new mod folder, not a recurring step. Never copy files into the game folder manually — if a mod folder isn't showing up in-game, check whether the symlink exists before copying anything.

## Development workflow

- Test incrementally against the real `UE4SS.log`, not just by reading the Lua. Write the smallest change that tests one thing, have the user launch/hot-reload, then read the log output back before continuing.
- Hot-reload (`Ctrl+R` in-game) restarts all mods without a full relaunch — prefer this over asking for a full relaunch when iterating.
- Widget class names, property names, and array structures for Remnant 2 cannot be guessed or inferred from generic UE documentation — they must come from live inspection (UE4SS Live View) or FModel with the community `.usmap` mapping file. Do not invent or assume a class path; if it's not already confirmed in the research doc, that's a research step to do first, not a detail to guess at.
- Only read the specific research doc sections and code relevant to the current task — don't re-read the entire research doc or reload unrelated mod folders' code into context for a focused change.
- When a finding changes the difficulty or approach of a mod (e.g. something turns out to be layout-graph-bound instead of a simple property patch), update `remnant2-modding-research.md` and flag it to the user clearly — this may change scope or priority.
- This is genuinely novel territory for Remnant 2 (no public precedent for in-game widget-injection mods on this game) — document findings as you go, even ones from failed approaches, since there's no existing mod to fall back on for reference.
