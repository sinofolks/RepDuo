"""Arrange existing calibration evidence, without retouching rendered pixels."""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, PngImagePlugin


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        raise ValueError(f"Refusing to overwrite {args.out}")
    base, candidate = [json.loads(path.read_text()) for path in (args.baseline, args.candidate)]
    assert base["protocol_id"] == candidate["protocol_id"], "Compare only one fixed protocol"
    panels = [("REFERENCE / CONCEPT", base["assets"]["reference"]),
              (f'{base["label"]} / {base["composite_score"]:.2f}', base["assets"]["candidate"]),
              (f'{candidate["label"]} / {candidate["composite_score"]:.2f}', candidate["assets"]["candidate"])]
    pictures = [Image.open(path).convert("RGB") for _, path in panels]
    width, height = pictures[0].size
    assert all(picture.size == (width, height) for picture in pictures)
    canvas = Image.new("RGB", (width*3, height+104), (10, 13, 15))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default(size=23)
    small = ImageFont.load_default(size=16)
    for index, ((label, _), picture) in enumerate(zip(panels, pictures)):
        draw.text((index*width+24, 21), label, font=font, fill=(226, 233, 236))
        canvas.paste(picture, (index*width, 60))
    draw.text((24, height+75), "Fixed camera, material, light and scoring. Single-view index, not a 3D fidelity percentage.",
              font=small, fill=(180, 190, 196))
    metadata = PngImagePlugin.PngInfo()
    metadata.add_text("Evidence", json.dumps({"baseline":str(args.baseline.resolve()),
                                            "candidate":str(args.candidate.resolve()),
                                            "protocol":candidate["protocol_id"],
                                            "operation":"side-by-side composition; source pixels unchanged"}))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(args.out, pnginfo=metadata)
    print(args.out.resolve())


if __name__ == "__main__":
    main()
