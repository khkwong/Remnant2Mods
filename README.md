# Remnant2Mods

Three [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) Lua mods for **Remnant 2**
(Steam/PC, Unreal Engine 5.2).

| Mod | What it does |
|---|---|
| [MoreLoadoutSlots](MoreLoadoutSlots/) | Raises the Character screen's loadout count from 8 to 20. |
| [LoadoutNamer](LoadoutNamer/) | Rename loadout tiles with F2; names persist across sessions. |
| [EquipmentSearch](EquipmentSearch/) | A working search bar for every inventory item grid, filtering by name and effect text. |

Each mod works standalone. See each mod's own README for details, and its
`mod.json` for version/author metadata.

## Requirements

- Remnant 2 (Steam/PC)
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) — experimental-latest build

## Installation

1. Copy the mod folder(s) you want into `<Remnant2>\Binaries\Win64\ue4ss\Mods\`.
2. Add a line for each in `ue4ss\Mods\mods.txt`, e.g.:
   ```
   MoreLoadoutSlots : 1
   LoadoutNamer : 1
   EquipmentSearch : 1
   ```
3. Launch the game.

## License

MIT — see [LICENSE](LICENSE). Free to use, modify, and redistribute with
attribution.
