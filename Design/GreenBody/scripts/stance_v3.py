"""Bounded, additive V3 standing-pose refinements, preserving mesh topology.

Called on a loaded V2 review rig. This does not change camera, materials, bone
lengths, mesh geometry or calibration settings. Diagnostic outputs are isolated.
"""

import argparse
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
DEFAULTS = {
    "foot_yaw_R": -38.0,
    "foot_yaw_L": 46.0,
    "knee_shift_R": [0.012, -0.018, 0.0],
    "ankle_shift_R": [-0.030, 0.010, 0.0],
    "knee_shift_L": [0.0, 0.0, 0.0],
    "ankle_shift_L": [-0.018, 0.0, 0.0],
}


def rotate_world(bone, rotation):
    pivot = bone.head.copy()
    bone.matrix = (Matrix.Translation(pivot)
                   @ rotation.to_matrix().to_4x4()
                   @ Matrix.Translation(-pivot) @ bone.matrix)
    bpy.context.view_layer.update()


def aim_chain(rig, start, end, target):
    bone = rig.pose.bones[start]
    current = rig.pose.bones[end].head - bone.head
    desired = Vector(target) - bone.head
    rotate_world(bone, current.normalized().rotation_difference(desired.normalized()))


def apply_stance(rig, params=None):
    """Preserve lengths; rotate leg chains toward bounded, asymmetric targets.

    Values named ``*_shift_*`` are world-space target offsets in meters, not
    translations of connected joints. Each target is reached by a rotation,
    retaining the actual chain length and contiguous skinning.
    """
    options = {**DEFAULTS, **(params or {})}
    initial = {side: {part: rig.pose.bones[prefix + "." + side].head.copy()
                      for part, prefix in (("hip", "upperleg01"),
                                           ("knee", "lowerleg01"), ("ankle", "foot"))}
               for side in ("L", "R")}
    for side in ("L", "R"):
        knee_target = initial[side]["knee"] + Vector(options["knee_shift_" + side])
        ankle_target = initial[side]["ankle"] + Vector(options["ankle_shift_" + side])
        aim_chain(rig, "upperleg01." + side, "lowerleg01." + side, knee_target)
        aim_chain(rig, "lowerleg01." + side, "foot." + side, ankle_target)
        foot = rig.pose.bones["foot." + side]
        # Absolute world-space yaw at the current ankle avoids inherited calf
        # twist lifting the sole. V2 already uses the same rest-frame convention.
        orientation = Quaternion((0, 0, 1), math.radians(options["foot_yaw_" + side]))
        orientation = orientation @ foot.bone.matrix_local.to_quaternion()
        matrix = orientation.to_matrix().to_4x4()
        matrix.translation = foot.head.copy()
        foot.matrix = matrix
        bpy.context.view_layer.update()
    rig["v3_stance_parameters"] = json.dumps(options, sort_keys=True)
    return options


def plant_feet(body, rig, floor_z=None, clearance=0.0005):
    """Plant the two soles via small pelvis-branch roll, counter-rotating legs.

    This is a bounded static support correction, not animation IK. MakeHuman's
    two pelvis branches permit slight hip-height asymmetry. The leg orientations
    and all bone lengths are retained; no vertex is flattened to the floor.
    """
    if floor_z is None:
        floor = bpy.data.objects.get("GB_Studio_Charcoal_Floor")
        if floor is None or floor.type != "MESH":
            raise ValueError("Pass floor_z explicitly when the review floor is absent")
        floor_z = min((floor.matrix_world @ vertex.co).z for vertex in floor.data.vertices)
    rolls = {"L": 0.0, "R": 0.0}
    def minima():
        evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh = evaluated.to_mesh()
        points = [evaluated.matrix_world @ v.co for v in mesh.vertices]
        evaluated.to_mesh_clear()
        return {side: min(p.z for p in points if sign * p.x > 0.04 and p.z < 0.2)
                for side, sign in (("L", 1), ("R", -1))}
    for _ in range(3):
        heights = minima()
        for side in ("L", "R"):
            displacement = floor_z + clearance - heights[side]
            if abs(displacement) < 0.0001:
                continue
            pelvis = rig.pose.bones["pelvis." + side]
            leg = rig.pose.bones["upperleg01." + side]
            across = leg.head.x - pelvis.head.x
            angle = -displacement / across
            if abs(rolls[side] + angle) > math.radians(8):
                raise ValueError("Support correction exceeds bounded 8-degree hip roll")
            orientation = leg.matrix.to_quaternion()
            rotate_world(pelvis, Quaternion((0, 1, 0), angle))
            matrix = orientation.to_matrix().to_4x4()
            matrix.translation = leg.head.copy()
            leg.matrix = matrix
            bpy.context.view_layer.update()
            rolls[side] += angle
    result = {"minimum_z_m": minima(), "floor_z_m": floor_z,
              "clearance_m": clearance,
              "pelvis_branch_roll_degrees": {side: math.degrees(v) for side, v in rolls.items()}}
    rig["v3_static_support"] = json.dumps(result, sort_keys=True)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--name", required=True)
    parser.add_argument("--params", default="{}")
    parser.add_argument("--plant", action="store_true")
    parser.add_argument("--views", nargs="*", default=[], choices=["Front", "Side", "Back"])
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    if not args.name.replace("-", "").replace("_", "").isalnum():
        raise ValueError("Name must be a short file-safe diagnostic label")
    out = ROOT / "renders" / "v3-stance-experiments" / args.name
    out.mkdir(parents=True, exist_ok=False)
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / "GreenBody-v2.blend"), use_scripts=False)
    rig = bpy.data.objects["GB_ReviewArmature"]
    parameters = apply_stance(rig, json.loads(args.params))
    body = bpy.data.objects["GreenBody"]
    support = plant_feet(body, rig) if args.plant else None
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    feet = {side: min((evaluated.matrix_world @ v.co).z for v in mesh.vertices
                      if sign * v.co.x > 0.04 and v.co.z < 0.2)
            for side, sign in (("L", 1), ("R", -1))}
    evaluated.to_mesh_clear()
    diagnostics = {"parameters": parameters, "feet_minimum_z": feet, "support": support,
                   "joints": {name: list(bone.head) for name, bone in rig.pose.bones.items()
                              if name.startswith(("upperleg01", "lowerleg01", "foot"))}}
    (out / "stance.json").write_text(json.dumps(diagnostics, indent=2) + "\n")
    bpy.context.scene["version"] = "V3 stance experiment " + args.name
    bpy.ops.wm.save_as_mainfile(filepath=str(out / "candidate.blend"))
    print("STANCE_EXPERIMENT", str(out / "candidate.blend"), flush=True)
    for view in args.views:
        scene = bpy.context.scene
        scene.camera = bpy.data.objects["GB_Camera_" + view]
        scene.cycles.device = "CPU"
        scene.cycles.samples = 24
        scene.render.resolution_x = 640
        scene.render.resolution_y = 800
        scene.render.resolution_percentage = 100
        scene.render.filepath = str(out / (view.lower() + ".png"))
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
