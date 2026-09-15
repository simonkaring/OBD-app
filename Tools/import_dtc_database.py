#!/usr/bin/env python3
"""Regenerate the offline DTC resource: python3 Tools/import_dtc_database.py.

Imports data only, not upstream executable code. The complete MIT notice and
source revision travel with the bundled JSON. Definitions are community data,
not verified model/year-specific repair instructions.
"""
import json
from pathlib import Path
import re
import sqlite3
import tempfile
from urllib.request import urlopen

REVISION = "04c43d72e7db7197658b6f72fe582c5076d9eee8"
SOURCE = "https://github.com/Wal33D/dtc-database"
BASE = f"https://raw.githubusercontent.com/Wal33D/dtc-database/{REVISION}/"


def main():
    license_text = urlopen(BASE + "LICENSE", timeout=60).read().decode("utf-8")
    data = urlopen(BASE + "data/dtc_codes.db", timeout=60).read()
    definitions = {}
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "dtc_codes.db"
        path.write_bytes(data)
        with sqlite3.connect(f"file:{path}?mode=ro", uri=True) as connection:
            rows = connection.execute(
                "SELECT manufacturer, code, description FROM dtc_definitions "
                "WHERE locale = 'en' ORDER BY manufacturer, code"
            ).fetchall()
        for manufacturer, code, description in rows:
            if not re.fullmatch(r"[PBCU][0-3][0-9A-F]{3}", code):
                raise ValueError(f"Invalid DTC: {code!r}")
            if not manufacturer or not description.strip():
                raise ValueError(f"Empty definition: {code}")
            # These are placeholders, not explanations of actual faults.
            if "manufacturer controlled dtc" in description.lower() or "reserved" in description.lower():
                continue
            definitions.setdefault(manufacturer, {})[code] = description.strip()

    assert definitions["GENERIC"]["P0301"] == "Cylinder 1 Misfire Detected"
    resource = dict(source=SOURCE, revision=REVISION, license=license_text,
                    definitions=definitions)
    destination = Path(__file__).resolve().parents[1] / "Data/Seed/wal33d_dtc.json"
    destination.write_text(json.dumps(resource, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Imported {sum(map(len, definitions.values()))} definitions to {destination}")


if __name__ == "__main__":
    main()
