# EquipmentSearch

A working search bar for your inventory.

## What it does

- Adds an always-visible search box to every inventory item grid: rings,
  amulets, armor, relics, weapons, and the Inventory tab's
  materials/quest/usable lists.
- Filters live as you type, matching both the item's name **and** its
  gameplay-effect text (so searching "grey health" finds trigger rings that
  grant it, not just items with those words in their name).
- The X button clears the search.
- Lore/flavor text is intentionally excluded from matching.

## Requirements

- Remnant 2 (Steam/PC)
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) — experimental-latest build

## Installation

1. Copy the `EquipmentSearch` folder into `<Remnant2>\Binaries\Win64\ue4ss\Mods\`.
2. Add a line for it in `ue4ss\Mods\mods.txt`:
   ```
   EquipmentSearch : 1
   ```
3. Launch the game.

## Known limitations

- The search filter resets when you switch tabs on the Inventory screen.
- An upgraded item keeps its old "+N" text in the search cache until you
  relaunch (its name still matches fine in the meantime).

## License

MIT — see the repository [LICENSE](../LICENSE).
