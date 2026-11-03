"""Real multiview Cycles evidence of a loaded V3 model; does not save the scene."""
import argparse
from pathlib import Path
import sys

import bpy
from mathutils import Vector


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--views", nargs="+", default=["Hero", "Front", "Side", "Back", "Head"])
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    assert bpy.app.background
    args.out.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24 if args.preview else 64
    scene.render.resolution_percentage = 60 if args.preview else 100
    for view in args.views:
        path = args.out / (view.lower()+".png")
        if path.exists():
            raise ValueError(f"Refusing to overwrite {path}")
        scene.render.resolution_x, scene.render.resolution_y = 1000, 1200
        if view in ("Head", "HeadBack", "HeadSide"):
            camera = bpy.data.objects["GB_Camera_Hero"].copy()
            camera.data = camera.data.copy()
            scene.collection.objects.link(camera)
            target = Vector((.015, -.025, 1.62))
            offset = {"Head": (-1.7, -5, .12), "HeadBack": (0, 5, .12), "HeadSide": (5, 0, .12)}[view]
            camera.location = target + Vector(offset)
            camera.rotation_euler = (target-camera.location).to_track_quat("-Z", "Y").to_euler()
            camera.data.ortho_scale = .61
            scene.render.resolution_y = 1000
        else:
            camera = bpy.data.objects["GB_Camera_"+view]
        scene.camera = camera
        scene.render.filepath = str(path.resolve())
        bpy.ops.render.render(write_still=True)
        print("V3_REVIEW_RENDER", str(path.resolve()), flush=True)


if __name__ == "__main__":
    main()
