"""Render saved Blender geometry, not AI-generated visual approximations.

Load GreenBody-v1.blend with --background --factory-startup, then run this script.
The saved model is not modified. Optional arguments: --views Front Side Back.
"""

import argparse
import sys
from pathlib import Path

import bpy


def main():
    if not bpy.app.background:
        raise RuntimeError("Use a separate background Blender process.")
    parser = argparse.ArgumentParser()
    parser.add_argument("--views", nargs="+", default=["Hero", "Front", "Side", "Back"],
                        choices=["Hero", "Front", "Side", "Back"])
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    root = Path(__file__).resolve().parents[1]
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 64
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 1200
    scene.render.resolution_percentage = 100
    for view in args.views:
        scene.camera = bpy.data.objects["GB_Camera_" + view]
        scene.render.filepath = str(root / "renders" / (view.lower() + ".png"))
        bpy.ops.render.render(write_still=True)
        print("GREEN_BODY_REVIEW_RENDER", scene.render.filepath, flush=True)


if __name__ == "__main__":
    main()
