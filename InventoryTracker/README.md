# InventoryTracker

**Work in progress — not yet functional as a player-facing mod.**

Shows which unique equippable items (rings, amulets, armor, weapons, weapon
mods, archetypes, mutators, traits) the player currently has vs. what's
missing.

Known limitation (by design, not a bug): the game has no persistent "ever
obtained" record for items, so this can only reflect what's currently in your
inventory — a sold/dismantled unique will show as missing again.

See `dev-docs/` and `docs/remnant2-modding-research.md` §3.10 for the research
behind this mod.

## Requirements

- Remnant 2 (Steam/PC)
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) — either experimental-latest or
  stable v3.0.1 Beta. **See the [repo README](../README.md#which-ue4ss-build-should-i-use)
  for which build to pick.**
