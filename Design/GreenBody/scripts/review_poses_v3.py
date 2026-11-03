"""Read-only source, static V3 squat/push-up deformation review.

Reuses the V2 articulated pose definitions unchanged. These are diagnostic
static poses, not animation clips, tracking support, or a biomechanical claim.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from review_poses import reset, update
from review_poses_v2 import (deep_squat, low_push_up, evaluated_points,
                            contact_report, joint_angle)
from validate_green_body import check_original_mesh, check_armature_weights


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def render_pose(source, out, name, pose_fn, samples, source_hash):
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    scene = bpy.context.scene
    original_version = scene.get("version")
    body = bpy.data.objects["GreenBody"]
    rig = next(modifier.object for modifier in body.modifiers if modifier.type == "ARMATURE")
    reset(rig)
    pose_fn(rig)
    floor = bpy.data.objects["GB_Studio_Charcoal_Floor"]
    floor_z = min((floor.matrix_world @ v.co).z for v in floor.data.vertices)
    points = evaluated_points(body)
    root = rig.pose.bones["root"]
    matrix = root.matrix.copy()
    matrix.translation.z += floor_z + .0005 - min(p.z for p in points)
    root.matrix = matrix
    update()
    points = evaluated_points(body)
    minimum = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    maximum = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    center = (minimum + maximum) / 2
    camera = bpy.data.objects["GB_Camera_Hero"]
    camera.location = center + Vector((-5.0, -3.2, .8) if name == "squat" else (5, -1.7, 1.2))
    camera.data.ortho_scale = 1.60 if name == "squat" else 2.03
    camera.rotation_euler = (center-camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.render.resolution_x = 960
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.filepath = str(out / (name + ".png"))
    scene["pose_review_only"] = True
    scene["approved_for_animation"] = False
    scene["version"] = f"V3 static deformation review — {source.stem} — {name}"
    report = {"schema": "greenbody-static-pose-review-v1", "source": str(source),
              "source_version": original_version, "source_sha256_before": source_hash,
              "pose": name, "pose_definition": "Unmodified V2 helper; all stored pose bases reset before posing",
              "status": "Static deformation QA only; not approved for animation or runtime tracking",
              "errors": [], "warnings": [],
              "render": {"width": 960, "height": 720, "samples": samples, "device": "CPU"},
              "bounds": {"minimum": list(minimum), "maximum": list(maximum)},
              "contact": contact_report(points, rig, floor_z, name),
              "knee_interior_angles_degrees": {side: joint_angle(rig, "upperleg01."+side, "lowerleg01."+side, "foot."+side)
                                                  for side in ("L", "R")},
              "hip_minus_knee_height_m": {side: rig.pose.bones["upperleg01."+side].head.z-rig.pose.bones["lowerleg01."+side].head.z
                                           for side in ("L", "R")},
              "limitations": ["Only two discrete diagnostic poses, not an animation sweep",
                              "No automatic self-intersection or collision test",
                              "Visual armpit and knee review required; a valid manifold does not prove good deformation",
                              "Contact measurements use geometric regions, not a dynamics or pressure simulation"],
              "pose_bones": {n: {"head": list(b.head), "tail": list(b.tail),
                                 "matrix_basis": [list(row) for row in b.matrix_basis]}
                             for n, b in rig.pose.bones.items()}}
    check_original_mesh(body, report)
    check_armature_weights(body, report)
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    report["evaluated_mesh"] = {"vertices": len(mesh.vertices), "faces": len(mesh.polygons),
                                "all_coordinates_finite": all(math.isfinite(c) for p in points for c in p),
                                "zero_area_faces": sum(p.area < 1e-12 for p in mesh.polygons)}
    evaluated.to_mesh_clear()
    if not report["evaluated_mesh"]["all_coordinates_finite"]:
        report["errors"].append("Nonfinite deformed surface")
    if report["evaluated_mesh"]["zero_area_faces"]:
        report["warnings"].append("Very small evaluated faces require inspection")
    update()
    projected = [world_to_camera_view(scene, camera, p) for p in points]
    report["render_framing"] = {"all_vertices_inside": all(0 <= p.x <= 1 and 0 <= p.y <= 1 and p.z > 0 for p in projected),
                                "screen_bounds": [[min(p[i] for p in projected), max(p[i] for p in projected)] for i in (0, 1)]}
    if not report["render_framing"]["all_vertices_inside"]:
        report["errors"].append("Pose render clips body vertices")
    assert not report["errors"], report["errors"]
    bpy.ops.wm.save_as_mainfile(filepath=str(out / (name + ".blend")))
    bpy.ops.render.render(write_still=True)
    report["source_sha256_after"] = digest(source)
    report["source_unchanged"] = source_hash == report["source_sha256_after"]
    assert report["source_unchanged"], "Source changed during diagnostic run"
    report["outputs"] = {suffix: {"path": str(out/(name+suffix)), "sha256": digest(out/(name+suffix))}
                         for suffix in (".png", ".blend")}
    (out / (name+"-report.json")).write_text(json.dumps(report, indent=2) + "\n")
    print("POSE_V3_REVIEW", name, str(out/(name+".png")), flush=True)
    return report


def main():
    if not bpy.app.background:
        raise RuntimeError("Use a separate background Blender process")
    parser = argparse.ArgumentParser()
    parser.add_argument("--blend", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--samples", type=int, default=32)
    parser.add_argument("--pose", choices=("both", "squat", "push-up"), default="both")
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    source, out = args.blend.resolve(), args.out.resolve()
    if not source.is_file() or source.suffix != ".blend":
        raise ValueError("Source must be an existing .blend")
    if out.exists():
        raise ValueError("Output must be a new directory; no diagnostic overwrite")
    out.mkdir(parents=True)
    source_hash = digest(source)
    reports = []
    for name, fn in (("squat", deep_squat), ("push-up", low_push_up)):
        if args.pose in ("both", name):
            reports.append(render_pose(source, out, name, fn, args.samples, source_hash))
    summary = {"source": str(source), "source_sha256": source_hash,
               "source_unchanged": digest(source) == source_hash,
               "pose_reports": [str(out/(r["pose"]+"-report.json")) for r in reports],
               "status": "Static pose evidence generated; visual review required, no animation approval"}
    (out / "summary.json").write_text(json.dumps(summary, indent=2)+"\n")


if __name__ == "__main__":
    main()
