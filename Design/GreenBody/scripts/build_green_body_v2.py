"""Build a separate, editable v2 reference study; never overwrite v1 or iOS."""

import argparse
import json
from pathlib import Path
import sys

import bpy

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from build_green_body import read_source, make_rig, assign_weights
from body_geometry_v2 import refine_body, review_posture, blend_neck_seam
from studio_v2 import setup_studio_v2, lime_material_v2


def main():
    if not bpy.app.background:
        raise RuntimeError("Use background Blender to preserve the user's open scene.")
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--head", choices=("v1", "v2"), default="v2")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if args.head == "v2":
        from head_geometry_v2 import rebuild_head
    else:
        from head_geometry import rebuild_head
    bpy.ops.wm.read_factory_settings(use_empty=True)
    points, faces = read_source()
    refine_body(points)
    scene = bpy.context.scene
    collection = bpy.data.collections.new("GB_Character")
    scene.collection.children.link(collection)
    mesh = bpy.data.meshes.new("GB_V2_ContinuousBody")
    mesh.from_pydata([tuple(point) for point in points[:13380]], [], faces)
    mesh.update()
    body = bpy.data.objects.new("GreenBody", mesh)
    collection.objects.link(body)
    for face in mesh.polygons:
        face.use_smooth = True
    body.data.materials.append(lime_material_v2())
    rig, _ = make_rig(points, collection)
    assign_weights(body, rig)
    rebuild_head(body)
    blend_neck_seam(body)
    review_posture(rig)
    smooth = body.modifiers.new("Subtle surface polish", "CORRECTIVE_SMOOTH")
    smooth.factor = 0.12
    smooth.iterations = 3
    smooth.use_pin_boundary = True
    subd = body.modifiers.new("Presentation subdivision", "SUBSURF")
    subd.levels = subd.render_levels = 2
    output = ROOT / "renders" / ("v2" if args.head == "v2" else "v2-experiments")
    output.mkdir(parents=True, exist_ok=True)
    cameras = setup_studio_v2(scene, output)
    scene.camera = cameras["Hero"]
    scene["version"] = "Green Body v2 — reference-led appearance study"
    scene["approved_for_animation"] = False
    scene["reference"] = str(ROOT / "reference/green-body-concept.png")
    body["source"] = "MakeHuman CC0 base/rig, custom torso and head geometry"
    body["status"] = "Appearance study only — not integrated into iOS"
    rig["purpose"] = "Static review posing; not approved for motion retargeting"
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                space = area.spaces.active
                space.shading.type = "SOLID"
                space.shading.color_type = "MATERIAL"
                space.overlay.show_overlays = False
                space.region_3d.view_perspective = "CAMERA"
    name = "GreenBody-v2.blend" if args.head == "v2" else "v2-experiments/body-study.blend"
    blend_path = ROOT / name if args.head == "v2" else ROOT / "renders" / name
    scene.render.filepath = str(output / "hero.png")
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    (output / "model-report.json").write_text(json.dumps({
        "version": "v2", "blender": bpy.app.version_string,
        "vertices": len(mesh.vertices), "faces": len(mesh.polygons),
        "bones": len(rig.data.bones), "head": args.head,
        "head_design": body.get("head_design", "v2 human mannequin"),
        "animation_approved": False,
    }, indent=2))
    if args.preview:
        scene.render.resolution_percentage = 60
        scene.cycles.samples = 24
    scene.render.filepath = str(output / ("preview-hero.png" if args.preview else "hero.png"))
    bpy.ops.render.render(write_still=True)
    print("GREEN_BODY_V2_RENDER", scene.render.filepath, flush=True)


if __name__ == "__main__":
    main()
