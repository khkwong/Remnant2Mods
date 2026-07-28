"""Match exported Armor_*.json pieces against wiki armor set names.

Each set is 1-4 separately-ownable pieces (Head/Body/Legs/Gloves) sharing
one internal dev asset-name suffix, e.g. Armor_Body_CrimsonGuard -> internal
name "CrimsonGuard". Groups by that name and labels each piece
"<Wiki Set Name> - <Slot>". Rebuilds dev-data/master_list/armor.json from a
fresh scan of dev-data/Exports/. See research doc 3.12 for full history.
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

PIECE_RE = re.compile(r"^Armor_(Head|Body|Legs|Gloves)_(.+)$")

# Dev placeholder/NPC-flavor pieces with no wiki entry - tutorial-area
# corpses and the base character body, not real collectible loot.
EXCLUDED_SETS = {"Default", "Nude", "FieldCap", "Bomber", "FlightTeamCap", "Adventurer", "Twisted"}

# Archetype starting armor (14 archetypes: 7 base + 3 starting-class variants
# + Ritualist/Invoker/Warden from DLC1-3) auto-unlocks with the archetype
# rather than being found as loot, so it isn't on the wiki's plain-loot list.
# Included anyway (user call, 2026-07-27): the ownership-check mechanism is
# identical either way, zero extra engineering cost; only the framing differs
# ("archetypes not yet unlocked" vs "loot possibly missed").
ARCHETYPE_SETS = {
    "Alchemist", "Archon", "Engineer", "Explorer", "Gunslinger", "Invader", "Summoner",
    "Challenger", "Handler", "Hunter", "Medic", "Ritualist", "Invoker", "Warden",
}

# Confirmed dev-internal-name -> wiki-display-name renames. Normalization
# can't bridge these - loot-set renames are pure user knowledge, and
# archetype-set names bear no resemblance to the archetype name at all
# (100% user-supplied pairings, 2026-07-27).
MANUAL_FIXES = {
    "Leto1": "Leto Mark 1",
    "Leto2": "Leto Mark II",
    "FaeRoyalGuard": "Fae Royal",
    "Army": "Battle",
    "NerudWarrior": "Phetyr",
    "RedPrince": "Crown of the Red Prince",
    "TopHat": "Dandy Topper",
    "PilotsHelm": "Navigator's Helm",
    "Alchemist": "Academic",
    "Challenger": "Bruiser",
    "Invader": "Dendroid",
    "Invoker": "Disciple",
    "Medic": "Field Medic",
    "Gunslinger": "High Noon",
    "Summoner": "Knotted",
    "Archon": "Labyrinth",
    "Hunter": "Nightstalker",
    "Explorer": "Realmwalker",
    "Engineer": "Technician",
    "Handler": "Trainer",
    "Ritualist": "Zealot",
    "Warden": "Nanoplated",
}


def collect_sets() -> dict:
    """internal set name -> list of (slot, package)."""
    sets: dict[str, list] = {}
    for p in EXPORTS.rglob("Armor_*.json"):
        if not is_real_item_file(p):
            continue
        m = PIECE_RE.match(p.stem)
        if not m:
            continue
        slot, internal_name = m.groups()
        package = find_package(p)
        if not package:
            continue
        sets.setdefault(internal_name, []).append((slot, package))
    return sets


def main():
    wiki_names = load_name_list(WIKI_DIR / "armor_names.txt")
    wiki_by_norm = {normalize(n): n for n in wiki_names}
    sets = collect_sets()

    matched, unmatched = [], []
    for internal_name, pieces in sets.items():
        if internal_name in EXCLUDED_SETS:
            continue
        wiki_name = wiki_by_norm.get(normalize(internal_name)) or MANUAL_FIXES.get(internal_name)
        if not wiki_name:
            unmatched.append({"internalName": internal_name, "pieceCount": len(pieces)})
            continue
        for slot, package in pieces:
            matched.append({"category": "Armor", "name": f"{wiki_name} - {slot}", "classPath": class_path(package)})

    matched.sort(key=lambda r: r["name"])
    write_json(OUT_DIR / "armor.json", matched)
    write_json(OUT_DIR / "armor_unmatched.json", unmatched)

    matched_set_count = len({r["name"].rsplit(" - ", 1)[0] for r in matched})
    print(f"Armor: {matched_set_count} sets matched ({len(matched)} pieces) of {len(wiki_names)} wiki names, {len(unmatched)} internal sets unmatched")


if __name__ == "__main__":
    main()
