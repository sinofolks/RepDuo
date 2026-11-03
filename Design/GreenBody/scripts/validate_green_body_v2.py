"""Reuse the read-only validator, keeping the v1 report untouched."""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import validate_green_body as checks

checks.OUTPUT = ROOT / "renders" / "v2" / "validation.json"
report = checks.main()
if report["errors"]:
    raise RuntimeError("V2 model validation failed; inspect renders/v2/validation.json")
