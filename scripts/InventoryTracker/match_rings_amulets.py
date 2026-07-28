"""Build the Rings/Amulets master-list entries by querying
remnant2.wiki.gg's Cargo API directly.

Rewritten 2026-07-28 from the original FModel-export-and-match version
(dev-data/Exports scan + normalize + manual fixes) after cross-checking this
API against that already-verified data: 328/328 exact classPath matches, 0
name mismatches, 0 gaps either direction. See research doc 3.14.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from lib import write_json, cargo_query

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "dev-data" / "master_list"

CLASSES = {"Ring": "Ring", "Amulet": "Amulet"}


def main():
    matched = []
    no_filepath = []

    for category, class_name in CLASSES.items():
        for row in cargo_query(class_name):
            filepath = row.get("filepath", "")
            if not filepath:
                no_filepath.append({"name": row["name"], "class": class_name})
                continue
            matched.append({"category": category, "name": row["name"], "classPath": filepath})

    matched.sort(key=lambda r: (r["category"], r["name"]))
    write_json(OUT_DIR / "rings_amulets.json", matched)
    if no_filepath:
        write_json(OUT_DIR / "rings_amulets_unmatched.json", no_filepath)
    else:
        (OUT_DIR / "rings_amulets_unmatched.json").unlink(missing_ok=True)

    print(f"Rings/Amulets: {len(matched)} matched from Cargo API, {len(no_filepath)} wiki entries with no filepath")


if __name__ == "__main__":
    main()
