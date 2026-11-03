"""Read-only structural verification of the saved V3 scene."""
from pathlib import Path
import argparse
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import validate_green_body

validate_green_body.OUTPUT = ROOT / "validation-v3.json"
if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=validate_green_body.OUTPUT)
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    if args.out.exists():
        raise ValueError(f"Refusing to overwrite {args.out}")
    validate_green_body.OUTPUT = args.out.resolve()
    result = validate_green_body.main()
    if result["errors"]:
        raise RuntimeError(result["errors"])
