"""Cross-check the existing FModel-built master-list categories
(rings_amulets/armor/mods) against remnant2.wiki.gg's Cargo API, to find
disagreements before trusting the API enough to retire dev-data/Exports/.

Read-only - writes a report to dev-data/api_crosscheck.json (NOT under
master_list/ - that directory must only ever contain category master-list
files, since generate_lua.py globs every *.json in it) and prints a summary.
Does not modify any existing master_list/*.json.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from lib import normalize, cargo_query

ROOT = Path(__file__).resolve().parents[2]
MASTER_LIST_DIR = ROOT / "dev-data" / "master_list"
REPORT_PATH = ROOT / "dev-data" / "api_crosscheck.json"

# Our category -> the Cargo `class` value(s) that should cover it.
CATEGORY_CLASSES = {
    "rings_amulets": ["Ring", "Amulet"],
    "armor": ["Body Armor", "Glove Armor", "Leg Armor", "Helmet"],
    "mods": ["Weapon Mod"],
}


def normalize_path(p: str) -> str:
    return p.strip().lower()


def main():
    report = {}
    for category, classes in CATEGORY_CLASSES.items():
        ours = json.loads((MASTER_LIST_DIR / f"{category}.json").read_text(encoding="utf-8"))
        our_paths = {normalize_path(e["classPath"]): e["name"] for e in ours}

        api_rows = []
        for c in classes:
            api_rows.extend(cargo_query(c))

        api_blank = [r for r in api_rows if not r.get("filepath")]
        api_with_path = [r for r in api_rows if r.get("filepath")]
        api_paths = {normalize_path(r["filepath"]): r["name"] for r in api_with_path}

        matched = []
        api_only = []
        our_only = []
        name_mismatches = []

        for path, api_name in api_paths.items():
            if path in our_paths:
                our_name = our_paths[path]
                matched.append(path)
                if normalize(our_name.split(" - ")[0]) not in normalize(api_name) and normalize(api_name) not in normalize(our_name):
                    name_mismatches.append({"classPath": path, "ourName": our_name, "apiName": api_name})
            else:
                api_only.append({"name": api_name, "classPath": path})

        for path, our_name in our_paths.items():
            if path not in api_paths:
                our_only.append({"name": our_name, "classPath": path})

        report[category] = {
            "ourCount": len(ours),
            "apiCount": len(api_rows),
            "apiBlankFilepath": len(api_blank),
            "matchedCount": len(matched),
            "apiOnly": api_only,
            "ourOnly": our_only,
            "nameMismatches": name_mismatches,
        }

        print(f"\n{category}: ours={len(ours)} api={len(api_rows)} ({len(api_blank)} blank filepath)")
        print(f"  matched classPath: {len(matched)}")
        print(f"  in API but not ours: {len(api_only)}")
        print(f"  in ours but not API: {len(our_only)}")
        print(f"  name differs (same classPath): {len(name_mismatches)}")

    REPORT_PATH.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\nFull report: {REPORT_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
