# PrismLegendaryReroller

Cleansing a Prism's legendary bonus no longer costs you a relevel.

## What it does

- Prisms cap at level 51, at which point a legendary (Mythic) bonus is rolled
  from a pool. Rerolling it normally requires "cleansing" it, which drops the
  Prism back to level 50 and forces you to relevel it before you can roll
  again — on top of the grind to reach 51 in the first place.
- This mod removes that penalty: after a legendary-only cleanse, the Prism
  stays at (or is instantly restored to) level 51, so you can roll again
  immediately.
- Cleansing the **whole Prism** (the separate action that resets it to level
  0 and clears every rolled stat segment, not just the legendary bonus) is
  untouched — this mod only affects the legendary-bonus-only cleanse.

## Requirements

- Remnant 2 (Steam/PC)
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) — experimental-latest
  recommended. **See the [repo README](../README.md#which-ue4ss-build-should-i-use)**
  for background on the experimental-latest vs. stable split if you also use
  asset/pak mods like `AllowModsMod`.

## Installation

1. Download `PrismLegendaryReroller-v1.2.0.zip` from the
   [Releases page](../../../releases) and extract it — you'll get a
   `PrismLegendaryReroller` folder containing `Scripts\`, `mod.json`, and
   this README.
2. Copy that folder into your UE4SS Mods folder:
   - Experimental-latest: `<Remnant2>\Binaries\Win64\ue4ss\Mods\`
   - Stable: `<Remnant2>\Binaries\Win64\Mods\`
3. Add a line for it in that folder's `mods.txt`:
   ```
   PrismLegendaryReroller : 1
   ```
4. Launch the game.

## Known limitations

- Only tested on UE4SS experimental-latest.
- Only affects the legendary-bonus-only cleanse; the whole-Prism reset
  behaves exactly as vanilla.

## License

MIT — see the repository [LICENSE](../LICENSE).
