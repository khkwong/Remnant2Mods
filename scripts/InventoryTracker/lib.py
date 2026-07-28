"""Shared helpers for InventoryTracker's master-list build pipeline.

Ported from PowerShell (2026-07-27) after hitting several PowerShell-specific
footguns in the original scripts: Where-Object collapsing a single match to
a non-countable scalar, ConvertFrom-Json nesting single-element JSON arrays
unpredictably, and Set-Content's default utf8 encoding silently adding a
BOM that broke Lua's parser. None of those exist in Python's stdlib json/
pathlib, which is why this pipeline lives here instead.
"""
import json
import re
import urllib.parse
import urllib.request
from pathlib import Path

# Sub-asset folders that are never the item's own defining file.
NON_ITEM_DIRS = {"Materials", "Material", "Textures", "VFX", "Animations"}

CARGO_API_URL = "https://remnant2.wiki.gg/api.php"


def normalize(s: str) -> str:
    """Strip non-alphanumerics and lowercase, for name-matching across
    dev-internal and wiki-display naming conventions."""
    return re.sub(r"[^a-zA-Z0-9]", "", s).lower()


def find_package(json_path: Path) -> str | None:
    """Return the first "Package" field found in an FModel-exported asset
    JSON array. Usually on the first (CDO) element, but a few files list a
    non-CDO object first instead (e.g. an AkComponent) - scan for it."""
    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    for obj in data:
        if isinstance(obj, dict) and obj.get("Package"):
            return obj["Package"]
    return None


def class_path(package: str) -> str:
    """Package path -> the ClassPath.ClassPath_C form main.lua compares
    against GetFullName() output."""
    last = package.rsplit("/", 1)[-1]
    return f"{package}.{last}_C"


def load_name_list(path: Path) -> list[str]:
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def cargo_query(class_name: str) -> list:
    """Query remnant2.wiki.gg's Cargo/Librarian API for every item of a
    given `class` (e.g. "Ring", "Long Gun", "Helmet"). Returns a list of
    {name, filepath, class} dicts - filepath is already the FULL classPath
    (Package.ClassName_C), not a bare Package path, unlike find_package()
    above.

    NOT uniformly trustworthy across all classes - "Weapon Mod" had ~15
    entries where filepath silently pointed to an unrelated crafting
    material instead of the mod itself (research doc 3.13). Sample and
    spot-check any new class against known-good data before trusting it.
    """
    params = {
        "action": "cargoquery",
        "tables": "items",
        "fields": "name,filepath,class",
        "where": f'class="{class_name}"',
        "format": "json",
        "limit": "500",
    }
    url = CARGO_API_URL + "?" + urllib.parse.urlencode(params)
    # remnant2.wiki.gg (MediaWiki) 403s requests with no/generic User-Agent.
    req = urllib.request.Request(url, headers={"User-Agent": "InventoryTracker-BuildPipeline/1.0 (Remnant2Mods repo)"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.load(resp)
    return [row["title"] for row in data.get("cargoquery", [])]


def is_real_item_file(path: Path) -> bool:
    """Excludes _Inspect companion files (3D inspect-viewport data, not the
    item def) and anything under a sub-asset folder."""
    if path.stem.endswith("_Inspect"):
        return False
    if any(part in NON_ITEM_DIRS for part in path.parts):
        return False
    return True
