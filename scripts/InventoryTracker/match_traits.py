"""Build the (Unlockable) Traits master-list entry from FModel exports.

Traits have no Cargo/API backing at all on remnant2.wiki.gg - confirmed
2026-07-28 by checking both the `items` table's `class` values (no `Trait`)
and the full list of Cargo tables the wiki exposes (no `traits` table under
any name). This category is FModel-export-only, no API step.

Unlike every other category so far, Trait assets carry a real plaintext
`Label`/`Description` directly on the class default object - no wiki name
matching needed at all (research doc 3.16). `AchievementTags` cleanly
separates the three trait kinds without relying on folder path (which is
inconsistent - e.g. "Amplitude" lives in a folder literally named
"Archetype" but is tagged as an ordinary unlockable, not an archetype trait):
  - StarterTrait  -> Core (always unlocked for everyone, nothing to track)
  - ArchetypeTrait -> Archetype trait (auto-granted with the archetype's own
    level - tracking would be redundant with the Engram category, which
    already tracks archetype/engram ownership correctly via the inventory
    item scan; this array's Level for archetype traits isn't even real
    player-allocated points, it just mirrors archetype level)
  - neither tag (plain "Trait"/"NonStarterTrait") -> Unlockable, the only
    kind this mod tracks. Confirmed via live ZZTestMod probe (research doc
    3.16): presence in the live TraitsComponent.Traits array reliably means
    "unlocked" for this group specifically - untouched unlockables are
    absent from the array entirely, not present-at-level-0.

EXCLUDED: Resonance and Wayfarer are exported trait assets with no wiki
match - confirmed by the user (from the wiki's own patch history) to be cut
content merged into Swiftness and Amplitude respectively during development.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from lib import write_json, write_master_list, class_path

ROOT = Path(__file__).resolve().parents[2]
EXPORTS = ROOT / "dev-data" / "Exports"
OUT_DIR = ROOT / "dev-data" / "master_list"
WIKI_REFERENCE = Path(__file__).parent / "wiki_data" / "traits_wiki_reference.json"

EXCLUDED = {"Resonance", "Wayfarer"}


def main():
    if not EXPORTS.is_dir():
        raise SystemExit(
            f"{EXPORTS} does not exist. This script needs an FModel export of "
            f"every World_*/Items/Traits/ folder (plus the two archetype-nested "
            f"exceptions, Items/Archetypes/Invoker/PerksAndTraits/Trait_Gifted.json "
            f"and Items/Archetypes/Warden/Traits/Trait_Barrier.json - those two are "
            f"filtered out anyway since they're Archetype-tagged, but harmless to "
            f"leave exported)."
        )

    if not WIKI_REFERENCE.exists():
        raise SystemExit(
            f"{WIKI_REFERENCE} does not exist - it's a tracked file (wiki source-"
            f"location text for each trait, hand-compiled from the wiki's raw "
            f"wikitext, not reproducible by any script), so its absence means "
            f"something is wrong with the checkout, not a data source that's "
            f"expected to sometimes be missing."
        )
    wiki_source = {}
    for t in json.loads(WIKI_REFERENCE.read_text(encoding="utf-8")):
        if t.get("group") == "Unlockable":
            wiki_source[t["name"]] = t.get("source")

    matched, skipped = [], []
    for p in EXPORTS.rglob("Trait_*.json"):
        if p.stem.endswith("_Stats"):
            continue
        data = json.loads(p.read_text(encoding="utf-8"))
        cdo = data[-1] if data else None
        if not isinstance(cdo, dict) or not cdo.get("Package"):
            continue

        props = cdo.get("Properties", {})
        tags = props.get("AchievementTags", [])
        label = props.get("Label", {}).get("SourceString")
        if not label:
            continue

        if label in EXCLUDED:
            skipped.append({"name": label, "reason": "confirmed cut/merged content"})
            continue
        if "ArchetypeTrait" in tags or "StarterTrait" in tags:
            skipped.append({"name": label, "reason": "Archetype or Core trait, out of scope", "tags": tags})
            continue

        matched.append({
            "category": "Trait",
            "name": label,
            "classPath": class_path(cdo["Package"]),
            "source": wiki_source.get(label),
        })

    matched.sort(key=lambda r: r["name"])
    write_master_list(OUT_DIR / "traits.json", matched)
    # Diagnostic only, not a master-list category file (no category/name/
    # classPath shape) - keep it out of OUT_DIR or generate_lua.py's glob
    # trips on it (research doc 3.14 hit this exact hazard already).
    write_json(ROOT / "dev-data" / "traits_skipped.json", skipped)

    no_source = [m["name"] for m in matched if not m.get("source")]
    print(f"Traits: {len(matched)} unlockable traits matched, {len(skipped)} skipped (core/archetype/cut)")
    if no_source:
        print(f"  WARNING: no wiki source text for: {', '.join(no_source)}")


if __name__ == "__main__":
    main()
