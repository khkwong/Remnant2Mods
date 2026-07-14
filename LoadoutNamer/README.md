# LoadoutNamer

Custom names for your loadout slots on the Character screen.

## What it does

- Hover a loadout tile and press **F2** — a text box opens right in the
  tile's title. Type a name, then **Enter** or **F2** to save it, **Escape**
  to cancel.
- Committing an empty name removes the custom name and restores the default
  ("Loadout N").
- The tile shows up to 18 characters (truncated with `..`); hovering shows
  the full name (up to 32 characters) in the tooltip, which also gets its
  own "F2 Rename" reminder.
- Names are saved to a text file next to the mod and persist across game
  sessions.

Pairs well with **MoreLoadoutSlots** (20 slots instead of 8) but works fine
on its own with the vanilla 8-slot panel.

## Requirements

- Remnant 2 (Steam/PC)
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) — experimental-latest build

## Installation

1. Copy the `LoadoutNamer` folder into `<Remnant2>\Binaries\Win64\ue4ss\Mods\`.
2. Add a line for it in `ue4ss\Mods\mods.txt`:
   ```
   LoadoutNamer : 1
   ```
3. Launch the game.

## Known limitations

- Names are shared per install, not per-character or per-save.
- The reserved "Last Gear State" auto-save slot can't be renamed.
- The edit box is a styled engine text box — close to the game's look, but
  not pixel-identical.

## License

MIT — see the repository [LICENSE](../LICENSE).
