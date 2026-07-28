"""Build the Weapons master-list entry by querying remnant2.wiki.gg's
Cargo/Librarian API directly, instead of scanning dev-data/Exports/.

Why: FModel export coverage kept lagging (69/113 weapons even after two
rounds of manual pakchunk exports), and ~20 "Standard" tier weapons use
generic internal names (Shotgun, Revolver, Staff...) that can't be mapped to
their real in-game name without external knowledge. The wiki's Cargo table
gives name+filepath directly and, for the Weapons classes specifically,
returned 113/113 complete with no bad data (cross-checked against
FModel-verified entries - exact string match). Contrast with the Weapon Mod
class, which had ~15 entries with filepaths silently pointing to unrelated
crafting materials instead of the mod itself - so this same approach is NOT
assumed safe for every category. Recheck for that failure pattern before
reusing this for a new category; see research doc 3.13.
"""
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from lib import write_json

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "dev-data" / "master_list"

API_URL = "https://remnant2.wiki.gg/api.php"
CLASSES = ["Long Gun", "Handgun", "Melee Weapon"]

# Polygun is one inventory item with two firing modes; the wiki lists it
# twice ("Polygun (Marksman)" / "Polygun (Shotgun)", same filepath) which
# would otherwise produce a duplicate master-list entry for one real item.
NAME_OVERRIDES = {
    "Polygun (Marksman)": "Polygun",
    "Polygun (Shotgun)": "Polygun",
}


def cargo_query(class_name: str) -> list:
    params = {
        "action": "cargoquery",
        "tables": "items",
        "fields": "name,filepath,class",
        "where": f'class="{class_name}"',
        "format": "json",
        "limit": "500",
    }
    url = API_URL + "?" + urllib.parse.urlencode(params)
    # remnant2.wiki.gg (MediaWiki) 403s requests with no/generic User-Agent.
    req = urllib.request.Request(url, headers={"User-Agent": "InventoryTracker-BuildPipeline/1.0 (Remnant2Mods repo)"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.load(resp)
    return [row["title"] for row in data.get("cargoquery", [])]


def main():
    matched = []
    seen_names = set()
    no_filepath = []

    for class_name in CLASSES:
        rows = cargo_query(class_name)
        for row in rows:
            name = NAME_OVERRIDES.get(row["name"], row["name"])
            filepath = row.get("filepath", "")
            if not filepath:
                no_filepath.append({"name": row["name"], "class": class_name})
                continue
            if name in seen_names:
                continue
            seen_names.add(name)
            # The wiki's filepath field is already the full
            # "Package.ClassName_C" form - no concatenation needed (unlike
            # FModel's raw "Package" field elsewhere in this pipeline).
            matched.append({"category": "Weapon", "name": name, "classPath": filepath})

    matched.sort(key=lambda r: r["name"])
    write_json(OUT_DIR / "weapons.json", matched)
    if no_filepath:
        write_json(OUT_DIR / "weapons_unmatched.json", no_filepath)

    print(f"Weapons: {len(matched)} matched from Cargo API, {len(no_filepath)} wiki entries with no filepath")


if __name__ == "__main__":
    main()
