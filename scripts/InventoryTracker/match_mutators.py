"""Build the Weapon/Armor Mutators master-list entry by querying
remnant2.wiki.gg's Cargo API directly.

Sampled 2026-07-28: the "Mutator" class returned 66 entries, all with a
filepath, no duplicate names. Filepaths point to MetaGem_<InternalName>
assets consistent with each entry's display name (e.g. "Bandit" ->
MetaGem_Bandit) - no evidence of the wrong-asset-type problem seen in
Weapon Mod (research doc 3.13). Treated as clean without a FModel
cross-check (no existing FModel-built mutators list to compare against).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from lib import write_json, write_master_list, cargo_query

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "dev-data" / "master_list"

CLASSES = ["Mutator"]


def main():
    matched = []
    no_filepath = []

    for class_name in CLASSES:
        for row in cargo_query(class_name):
            filepath = row.get("filepath", "")
            if not filepath:
                no_filepath.append({"name": row["name"], "class": class_name})
                continue
            matched.append({"category": "Mutator", "name": row["name"], "classPath": filepath})

    matched.sort(key=lambda r: r["name"])
    write_master_list(OUT_DIR / "mutators.json", matched)
    if no_filepath:
        write_json(OUT_DIR / "mutators_unmatched.json", no_filepath)
    else:
        (OUT_DIR / "mutators_unmatched.json").unlink(missing_ok=True)

    print(f"Mutators: {len(matched)} matched from Cargo API, {len(no_filepath)} wiki entries with no filepath")


if __name__ == "__main__":
    main()
