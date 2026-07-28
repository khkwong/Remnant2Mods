"""Build the Armor master-list entries by querying remnant2.wiki.gg's
Cargo API directly, using its real per-piece display names.

Rewritten 2026-07-28 from the original FModel-export-and-match version
(internal-name grouping + a MANUAL_FIXES dict of ~20 user-supplied name
pairings, since dev-internal set names bear no resemblance to the real
per-piece names). The Cargo API's Body/Glove/Leg Armor + Helmet classes give
each piece's actual name directly ("Academic's Hat", "Crimson Guard
Gauntlets", "Void Carapace") - no grouping or guessing needed at all.

Cross-checked against the old FModel-verified 120-piece list: 119/120 exact
classPath matches. The 1 gap each direction: "Survivor - Head" isn't in the
wiki's Helmet table at all (a wiki gap, not our error - kept via the
FALLBACK_ENTRIES below); "Field Medic Hat" (Armor_Head_FieldCap) turned out
to be a real named item we'd wrongly excluded as a dev placeholder in the
old pipeline - the API catches this for free. See research doc 3.14.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from lib import write_json, cargo_query

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "dev-data" / "master_list"

CLASSES = ["Body Armor", "Glove Armor", "Leg Armor", "Helmet"]

# Confirmed real items missing from the wiki's Cargo tables (spot-checked
# against FModel exports 2026-07-28) - not derivable from the API, kept by
# hand until/unless the wiki adds them.
FALLBACK_ENTRIES = [
    {"category": "Armor", "name": "Survivor Helmet", "classPath": "/Game/World_Base/Items/Armor/Survivor/Armor_Head_Survivor.Armor_Head_Survivor_C"},
]


def main():
    matched = []
    no_filepath = []

    for class_name in CLASSES:
        for row in cargo_query(class_name):
            filepath = row.get("filepath", "")
            if not filepath:
                no_filepath.append({"name": row["name"], "class": class_name})
                continue
            matched.append({"category": "Armor", "name": row["name"], "classPath": filepath})

    matched.extend(FALLBACK_ENTRIES)
    matched.sort(key=lambda r: r["name"])
    write_json(OUT_DIR / "armor.json", matched)
    if no_filepath:
        write_json(OUT_DIR / "armor_unmatched.json", no_filepath)
    else:
        (OUT_DIR / "armor_unmatched.json").unlink(missing_ok=True)

    print(f"Armor: {len(matched)} matched ({len(matched) - len(FALLBACK_ENTRIES)} from Cargo API + {len(FALLBACK_ENTRIES)} fallback), {len(no_filepath)} wiki entries with no filepath")


if __name__ == "__main__":
    main()
