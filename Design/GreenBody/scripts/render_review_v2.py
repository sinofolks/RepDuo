"""True Cycles renders of the saved v2 model, with no geometry modification."""

import argparse
from pathlib import Path
import sys

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--views", nargs="+", default=["Hero", "Front", "Side", "Back", "Head"],
                        choices=["Hero", "Front", "Side", "Back", "Head"])
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if not bpy.app.background:
        raise RuntimeError("Use a separate background Blender process.")
    scene = bpy.context.scene
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24 if args.preview else 64
    scene.render.resolution_percentage = 60 if args.preview else 100
    for view in args.views:
        scene.render.resolution_x = 1000
        scene.render.resolution_y = 1200
        if view == "Head":
            camera = bpy.data.objects["GB_Camera_Hero"].copy()
            camera.data = camera.data.copy()
            scene.collection.objects.link(camera)
            target = Vector((0, -0.025, 1.62))
            camera.location = target + Vector((-1.70, -5, 0.12))
            camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
            camera.data.ortho_scale = 0.61
            scene.camera = camera
            scene.render.resolution_y = 1000
        else:
            scene.camera = bpy.data.objects["GB_Camera_" + view]
        filename = ("preview-" if args.preview else "") + view.lower() + ".png"
        scene.render.filepath = str(ROOT / "renders" / "v2" / filename)
        bpy.ops.render.render(write_still=True)
        print("V2_REVIEW_RENDER", scene.render.filepath, flush=True)


if __name__ == "__main__":
    main()
