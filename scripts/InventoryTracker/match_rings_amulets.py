"""Match exported Ring_*/Amulet_*.json assets against wiki name lists.

Rebuilds dev-data/master_list/rings_amulets.json from a fresh scan of
dev-data/Exports/ - safe to re-run any time exports change. See research doc
3.11 for the full history behind this list (the pakchunk0/1 export gap,
the manual-fix pairings, the BlessedNecklace exclusion).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from lib import normalize, find_package, load_name_list, write_json, class_path, is_real_item_file

ROOT = Path(__file__).resolve().parents[2]
EXPORTS = ROOT / "dev-data" / "Exports"
WIKI_DIR = Path(__file__).parent / "wiki_data"
OUT_DIR = ROOT / "dev-data" / "master_list"

# Confirmed dev-internal-name -> wiki-display-name renames (normalization
# can't catch reworded/abbreviated names). Confirmed 2026-07-27, 5 of them
# (BrightSteelRing/PanMageSigil/StrongArmBand/DowngradedRing/FocusedJewel)
# user-verified in-game (owns all 5).
MANUAL_FIXES = {
    "RingOfTheAdmiral": "Worn Admiral's Ring",
    "DevouringLoop": "Devoured Loop",
    "DranScavengerSigil": "Dran Scavenger Ring",
    "BrazenAlloy": "Brazen Amalgam",
    "PoisonStone": "Acid Stone",
    "EncryptedLoop": "Encrypted Ring",
    "ShadeBloomFloret": "Shaed Bloom Crystal",
    "BrightSteelRing": "Dull Steel Ring",
    "PanMageSigil": "Ahanae Crystal",
    "StrongArmBand": "Ring of the Damned",
    "DowngradedRing": "Embrace of Sha'Hala",
    "FocusedJewel": "Focusing Shard",
}

# No wiki match at all. BlessedNecklace confirmed as an item from the
# original Remnant: From the Ashes, likely a leftover/misimported dev asset,
# not a real obtainable Remnant 2 item.
EXCLUDED = {"BlessedNecklace"}


def collect_canonical(prefix: str) -> dict:
    """folder -> (package, path). Dedups companion files (_Action/_Aura/
    _Shield variants etc aren't separate items) to the shortest Package
    string in the folder - the canonical item definition."""
    canonical = {}
    for p in EXPORTS.rglob(f"{prefix}*.json"):
        if not is_real_item_file(p):
            continue
        package = find_package(p)
        if not package:
            continue
        folder = p.parent
        if folder not in canonical or len(package) < len(canonical[folder][0]):
            canonical[folder] = (package, p)
    return canonical


def match_category(category: str, prefix: str, wiki_names: list[str]):
    canonical = collect_canonical(prefix)
    wiki_by_norm = {normalize(n): n for n in wiki_names}

    matched, unmatched = [], []
    for folder, (package, path) in canonical.items():
        folder_name = folder.name
        file_base = path.stem[len(prefix):] if path.stem.startswith(prefix) else path.stem

        if folder_name in EXCLUDED or file_base in EXCLUDED:
            continue

        wiki_name = (
            wiki_by_norm.get(normalize(folder_name))
            or wiki_by_norm.get(normalize(file_base))
            or MANUAL_FIXES.get(folder_name)
            or MANUAL_FIXES.get(file_base)
        )
        if not wiki_name:
            unmatched.append({"folder": folder_name, "package": package})
            continue

        matched.append({"category": category, "name": wiki_name, "classPath": class_path(package)})
    return matched, unmatched


def main():
    ring_names = load_name_list(WIKI_DIR / "ring_names.txt")
    amulet_names = load_name_list(WIKI_DIR / "amulet_names.txt")

    ring_matched, ring_unmatched = match_category("Ring", "Ring_", ring_names)
    amulet_matched, amulet_unmatched = match_category("Amulet", "Amulet_", amulet_names)

    matched = sorted(ring_matched + amulet_matched, key=lambda r: (r["category"], r["name"]))
    write_json(OUT_DIR / "rings_amulets.json", matched)
    write_json(OUT_DIR / "rings_amulets_unmatched.json", ring_unmatched + amulet_unmatched)

    print(f"Rings: {len(ring_matched)}/{len(ring_names)} wiki names matched, {len(ring_unmatched)} exported assets unmatched")
    print(f"Amulets: {len(amulet_matched)}/{len(amulet_names)} wiki names matched, {len(amulet_unmatched)} exported assets unmatched")


if __name__ == "__main__":
    main()
