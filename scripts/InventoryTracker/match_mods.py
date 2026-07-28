"""Match standalone weapon mod assets against the wiki's swappable-mod list.

Only Items/Mods/<Name>/Mod_<Name>.json files count - weapon-embedded
signature mods (Items/Weapons/*/Mod/Mod_<Name>.json) are permanently baked
into specific Special/Archetype weapons and aren't separately owned/
swappable (owning one just means owning that weapon). Rebuilds
dev-data/master_list/mods.json from a fresh scan of dev-data/Exports/. See
research doc 3.12 for full history.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from lib import normalize, find_package, load_name_list, write_json, class_path, is_real_item_file

ROOT = Path(__file__).resolve().parents[2]
EXPORTS = ROOT / "dev-data" / "Exports"
WIKI_DIR = Path(__file__).parent / "wiki_data"
OUT_DIR = ROOT / "dev-data" / "master_list"

# A real per-item file is exactly "Mod_<Name>.json" - excludes helper assets
# sharing the Mod_ prefix (Mod_KnightGuard_01.json, Mod_KnightGuard_Skeleton
# .json, Mod_EnergyWall_Shield.json, Mod_Ouroboros_Aura.json, etc).
MOD_FILE_RE = re.compile(r"^Mod_[A-Za-z0-9]+$")

# Confirmed dev-internal-name -> wiki-display-name rename (version-suffix
# mismatch, not a real naming difference).
MANUAL_FIXES = {"Skewer": "Skewer 2.0"}

# Exported files with no wiki match at all - likely cut/leftover content.
# FlickerCloak is a confirmed Remnant 1 (From the Ashes) mod, same pattern
# as the BlessedNecklace amulet in Phase 1. Bloodtrail/MoltenShot/
# NoxiousBolt unconfirmed either way; excluded pending further research.
EXCLUDED = {"Bloodtrail", "FlickerCloak", "MoltenShot", "NoxiousBolt"}


def is_standalone(path: Path) -> bool:
    return "Weapons" not in path.parts


def main():
    wiki_names = load_name_list(WIKI_DIR / "mod_names.txt")
    wiki_by_norm = {normalize(n): n for n in wiki_names}

    matched, unmatched = [], []
    for p in EXPORTS.rglob("Mod_*.json"):
        if not MOD_FILE_RE.match(p.stem):
            continue
        if not is_real_item_file(p) or not is_standalone(p):
            continue
        package = find_package(p)
        if not package:
            continue

        base = p.stem[len("Mod_"):]
        if base in EXCLUDED:
            continue

        wiki_name = wiki_by_norm.get(normalize(base)) or MANUAL_FIXES.get(base)
        if not wiki_name:
            unmatched.append({"base": base, "package": package})
            continue

        matched.append({"category": "Mod", "name": wiki_name, "classPath": class_path(package)})

    matched.sort(key=lambda r: r["name"])
    write_json(OUT_DIR / "mods.json", matched)
    write_json(OUT_DIR / "mods_unmatched.json", unmatched)

    print(f"Mods: {len(matched)}/{len(wiki_names)} wiki names matched, {len(unmatched)} exported assets unmatched")


if __name__ == "__main__":
    main()
