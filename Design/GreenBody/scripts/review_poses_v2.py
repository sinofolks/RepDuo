"""Reference-led static pose studies of GreenBody-v2, not motion approval.

Reads the neutral v2 scene without changing it. Writes only renders/v2/poses.
The v1 posing module is imported for read-only math helpers, never executed.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "renders" / "v2" / "poses"
sys.path.insert(0, str(ROOT / "scripts"))
from review_poses import update, rotate_world, aim_chain, set_world_rotation, palm_down, reset, root_pose
from validate_green_body import check_original_mesh, check_armature_weights


def evaluated_points(body):
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
    evaluated.to_mesh_clear()
    return points


def relax_fingers(rig, side):
    sign = 1 if side == "L" else -1
    for finger, spread in ((2, -0.065), (3, 0), (4, 0.05), (5, 0.11)):
        for part in range(1, 4):
            bone = rig.pose.bones.get(f"finger{finger}-{part}.{side}")
            if bone is not None:
                direction = (bone.tail - bone.head).normalized()
                desired = Vector((sign * spread, -1, -0.035)).normalized()
                rotate_world(bone, direction.rotation_difference(desired))
    # Thumb is abducted beside the palm, not left hanging below the wrist.
    for part in range(1, 4):
        bone = rig.pose.bones.get(f"finger1-{part}.{side}")
        if bone is not None:
            direction = (bone.tail - bone.head).normalized()
            desired = Vector((-sign * (0.76 if part == 1 else 0.54), -0.74, 0.015)).normalized()
            rotate_world(bone, direction.rotation_difference(desired))


def deep_squat(rig):
    root_pose(rig, 34, 0.44)
    for side, sign in (("L", 1), ("R", -1)):
        aim_chain(rig, "upperleg01." + side, "lowerleg01." + side, (sign * 0.20, -0.95, 0.25))
        aim_chain(rig, "lowerleg01." + side, "foot." + side, (sign * 0.025, 0.40, -0.92))
        foot = rig.pose.bones["foot." + side]
        set_world_rotation(foot, foot.bone.matrix_local.to_quaternion())
        aim_chain(rig, "upperarm01." + side, "lowerarm01." + side, (sign * 0.018, -1, -0.008))
        aim_chain(rig, "lowerarm01." + side, "wrist." + side, (-sign * 0.02, -1, -0.008))
        palm_down(rig, side)
        relax_fingers(rig, side)
    rotate_world(rig.pose.bones["neck01"], Quaternion((1, 0, 0), math.radians(-15)))


def low_push_up(rig):
    root_pose(rig, 85, 0.31)
    for side, sign in (("L", 1), ("R", -1)):
        aim_chain(rig, "upperarm01." + side, "lowerarm01." + side, (sign * 0.31, 0.93, -0.16))
        aim_chain(rig, "lowerarm01." + side, "wrist." + side, (-sign * 0.008, -0.26, -0.965))
        palm_down(rig, side)
        relax_fingers(rig, side)
    rotate_world(rig.pose.bones["neck01"], Quaternion((1, 0, 0), math.radians(-9)))
    # Bounded static support solve; no controls, keyframes or runtime retargeting.
    low, high = 0.02, 0.42
    body = bpy.data.objects["GreenBody"]
    for _ in range(9):
        slope = (low + high) / 2
        for side, sign in (("L", 1), ("R", -1)):
            aim_chain(rig, "upperleg01." + side, "lowerleg01." + side, (sign * 0.025, 1, -slope))
            aim_chain(rig, "lowerleg01." + side, "foot." + side, (sign * 0.012, 1, -slope))
            foot = rig.pose.bones["foot." + side]
            rotation = Quaternion((1, 0, 0), math.radians(67)) @ foot.bone.matrix_local.to_quaternion()
            set_world_rotation(foot, rotation)
        points = evaluated_points(body)
        toe_height = min(point.z for point in points if point.y > 0.70)
        hand_height = min(point.z for point in points if abs(point.x) > 0.12 and point.y < 0.05)
        if toe_height > hand_height:
            low = slope
        else:
            high = slope


def joint_angle(rig, a, b, c):
    pa, pb, pc = (rig.pose.bones[name].head for name in (a, b, c))
    return math.degrees((pa - pb).angle(pc - pb))


def contact_report(points, rig, floor_z, pose_name):
    report = {"floor_z_m": floor_z, "global_minimum_z_m": min(p.z for p in points), "feet": {}}
    for side, sign in (("L", 1), ("R", -1)):
        ankle = rig.pose.bones["foot." + side].head
        foot_points = [p for p in points if sign * p.x > 0.035
                       and abs(p.y - ankle.y) < 0.32 and p.z < ankle.z + 0.015]
        heel_points = [p for p in foot_points if p.y > ankle.y - 0.015]
        report["feet"][side] = {"minimum_z_m": min(p.z for p in foot_points),
                                   "support_gap_m": min(p.z for p in foot_points) - floor_z,
                                   "heel_minimum_z_m": min((p.z for p in heel_points), default=None)}
    if pose_name == "push-up":
        report["hands"] = {side: {"minimum_z_m": min(p.z for p in points if sign*p.x > 0.12 and p.y < 0.05),
                                   "support_gap_m": min(p.z for p in points if sign*p.x > 0.12 and p.y < 0.05) - floor_z}
                           for side, sign in (("L", 1), ("R", -1))}
    return report


def render_pose(name, pose_fn, samples):
    source = ROOT / "GreenBody-v2.blend"
    bpy.ops.wm.open_mainfile(filepath=str(source))
    scene = bpy.context.scene
    rig = bpy.data.objects["GB_ReviewArmature"]
    body = bpy.data.objects["GreenBody"]
    reset(rig)
    pose_fn(rig)
    floor = bpy.data.objects["GB_Studio_Charcoal_Floor"]
    floor_z = min((floor.matrix_world @ vertex.co).z for vertex in floor.data.vertices)
    points = evaluated_points(body)
    root = rig.pose.bones["root"]
    matrix = root.matrix.copy()
    matrix.translation.z += floor_z + 0.0005 - min(p.z for p in points)
    root.matrix = matrix
    update()
    points = evaluated_points(body)
    minimum = Vector(tuple(min(point[i] for point in points) for i in range(3)))
    maximum = Vector(tuple(max(point[i] for point in points) for i in range(3)))
    center = (minimum + maximum) / 2
    camera = bpy.data.objects["GB_Camera_Hero"]
    if name == "squat":
        camera.location = center + Vector((-5.0, -3.2, 0.8))
        camera.data.ortho_scale = 1.60
    else:
        camera.location = center + Vector((5.0, -1.7, 1.20))
        camera.data.ortho_scale = 2.03
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.render.resolution_x = 960
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.filepath = str(OUT / (name + ".png"))
    scene["pose_review_only"] = True
    scene["approved_for_animation"] = False
    scene["version"] = "Green Body v2 — " + name + " static appearance study"
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                space = area.spaces.active
                space.shading.type = "SOLID"
                space.shading.color_type = "MATERIAL"
                space.overlay.show_overlays = False
                space.region_3d.view_perspective = "CAMERA"
    report = {"errors": [], "warnings": [], "source": str(source),
              "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
              "status": "Static pose review only. No animation or runtime movement approved.",
              "render": {"width": 960, "height": 720, "samples": samples, "device": "CPU"},
              "bounds": {"minimum": list(minimum), "maximum": list(maximum)},
              "contact": contact_report(points, rig, floor_z, name),
              "knee_interior_angles_degrees": {side: joint_angle(rig, "upperleg01." + side, "lowerleg01." + side, "foot." + side)
                                                  for side in ("L", "R")},
              "hip_minus_knee_height_m": {side: rig.pose.bones["upperleg01." + side].head.z - rig.pose.bones["lowerleg01." + side].head.z
                                           for side in ("L", "R")},
              "pose_bones": {n: {"head": list(b.head), "tail": list(b.tail), "matrix_basis": [list(row) for row in b.matrix_basis]}
                             for n, b in rig.pose.bones.items()}}
    check_original_mesh(body, report)
    check_armature_weights(body, report)
    assert not report["errors"], report["errors"]
    receivers = bpy.data.collections.get("GB_V2_CharacterLightReceivers")
    assert receivers and body.name in receivers.objects, "Preserve v2 character light linking"
    (OUT / (name + "-report.json")).write_text(json.dumps(report, indent=2))
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / (name + ".blend")))
    bpy.ops.render.render(write_still=True)
    print("POSE_V2_REVIEW", name, scene.render.filepath, flush=True)


if __name__ == "__main__":
    if not bpy.app.background:
        raise RuntimeError("Run with a separate background Blender process.")
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", type=int, default=32)
    parser.add_argument("--pose", choices=("both", "squat", "push-up"), default="both")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    OUT.mkdir(parents=True, exist_ok=True)
    if args.pose in ("both", "squat"):
        render_pose("squat", deep_squat, args.samples)
    if args.pose in ("both", "push-up"):
        render_pose("push-up", low_push_up, args.samples)
