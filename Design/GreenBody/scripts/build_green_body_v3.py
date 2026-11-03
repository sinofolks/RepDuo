"""Additive, reproducible V3 sculpt/pose study; V2 and scoring remain immutable.

Run in background Blender with -- --out PATH [--params JSON] [--stance].
All distances are meters. Parameters affect actual mesh/rig, never the camera.
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
sys.path.insert(0, str(ROOT / "scripts"))
from build_green_body import smoothstep
from body_geometry_v2 import _rotate

DEFAULTS = {"head_yaw": 18.0, "neck_lean": 8.0, "head_counterlean": -6.0,
            "right_arm_in": 4.0, "face_relief": 0.45, "neck_polish": 1.0,
            "chest_polish": 0.55, "arm_volume": 0.045, "body_yaw": 0.0,
            "chest_plane": 0.0, "spine_lean": 0.0, "right_forearm_out": 0.0,
            "left_arm_in": 0.0, "left_forearm_out": 0.0}


def gaussian(value, center, width):
    return math.exp(-0.5 * ((value - center) / width) ** 2)


def polish(body, params):
    mesh = body.data
    # Undo part of the V2 face relief with the same smooth, symmetric fields.
    # Keeping the existing connected topology retains every skin assignment.
    for vertex in mesh.vertices:
        x, y, z = vertex.co
        front = 1 - smoothstep(-0.095, -0.035, y)
        if z > 1.61:
            sockets = gaussian(x, .029, .014) + gaussian(x, -.029, .014)
            brows = gaussian(x, .029, .019) + gaussian(x, -.029, .019)
            relief = .0012 * sockets * gaussian(z, 1.698, .012)
            relief -= .00035 * brows * gaussian(z, 1.713, .010)
            relief -= .005 * gaussian(x, 0, .011) * gaussian(z, 1.698, .020)
            relief -= .0105 * gaussian(x, 0, .015) * gaussian(z, 1.679, .0125)
            vertex.co.y -= params["face_relief"] * relief * front
        # Small broad sculpt strokes; preserve jaw and lateral neck silhouette.
        if 1.49 < z < 1.62:
            vertex.co.y += .003 * params["neck_polish"] * front * gaussian(x, 0, .038) * gaussian(z, 1.569, .023)
        if 1.245 < z < 1.49:
            weight = smoothstep(1.245, 1.285, z)*(1-smoothstep(1.435, 1.49, z))
            weight *= 1-smoothstep(.10, .18, abs(x))
            weight *= 1-smoothstep(-.105, -.045, y)
            target = -.082-.064*gaussian(z, 1.335, .072)+.020*(x/.14)**2
            vertex.co.y += max(-.006, min(.006, target-y))*weight*params["chest_plane"]

    neighbors = [[] for _ in mesh.vertices]
    for edge in mesh.edges:
        a, b = edge.vertices
        neighbors[a].append(b)
        neighbors[b].append(a)
    # Longitudinally broad surface polish avoids making a second neck seam.
    for _ in range(12):
        positions = [v.co.copy() for v in mesh.vertices]
        for vertex in mesh.vertices:
            x, y, z = positions[vertex.index]
            neck = smoothstep(1.50, 1.535, z) * (1-smoothstep(1.602, 1.637, z))
            neck *= params["neck_polish"]
            chest = gaussian(z, 1.335, .082) * (1-smoothstep(.10, .19, abs(x)))
            chest *= (1-smoothstep(-.10, -.025, y)) * params["chest_polish"]
            weight = max(neck * .30, chest * .42)
            if weight > .001 and neighbors[vertex.index]:
                mean = sum((positions[i] for i in neighbors[vertex.index]), Vector()) / len(neighbors[vertex.index])
                vertex.co += (mean - positions[vertex.index]) * weight

    # Local radial biceps/triceps volume in REST space; no limb length scaling.
    rig = next(m.object for m in body.modifiers if m.type == "ARMATURE")
    for side in ("L", "R"):
        start = rig.data.bones["upperarm01." + side].head_local
        end = rig.data.bones["lowerarm01." + side].head_local
        axis = end-start
        for vertex in mesh.vertices:
            offset = vertex.co-start
            t = offset.dot(axis)/axis.length_squared
            radial = offset-axis*t
            if .12 < t < .94 and radial.length < .085:
                weight = smoothstep(.12, .35, t)*(1-smoothstep(.72, .94, t))
                weight *= 1-smoothstep(.055, .085, radial.length)
                vertex.co += radial * params["arm_volume"] * weight
    mesh.update()


def upper_pose(rig, params):
    _rotate(rig.pose.bones["spine05"], Quaternion((0, 1, 0), math.radians(params["spine_lean"])))
    _rotate(rig.pose.bones["upperarm01.R"], Quaternion((0, 1, 0), math.radians(-params["right_arm_in"])))
    _rotate(rig.pose.bones["lowerarm01.R"], Quaternion((0, 1, 0), math.radians(params["right_forearm_out"])))
    _rotate(rig.pose.bones["upperarm01.L"], Quaternion((0, 1, 0), math.radians(params["left_arm_in"])))
    _rotate(rig.pose.bones["lowerarm01.L"], Quaternion((0, 1, 0), math.radians(-params["left_forearm_out"])))
    _rotate(rig.pose.bones["neck01"], Quaternion((0, 1, 0), math.radians(params["neck_lean"])))
    _rotate(rig.pose.bones["head"], Quaternion((0, 1, 0), math.radians(params["head_counterlean"])))
    # Spread yaw through the neck so the head does not swivel at one seam.
    for bone, weight in (("neck01", .25), ("neck02", .25), ("head", .5)):
        _rotate(rig.pose.bones[bone], Quaternion((0, 0, 1), math.radians(params["head_yaw"] * weight)))


def main():
    if not bpy.app.background:
        raise RuntimeError("Background only: preserve the user's open Blender scene")
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--params", type=Path)
    parser.add_argument("--stance", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    destination = args.out.resolve()
    if destination.exists():
        raise ValueError(f"Refusing to overwrite {destination}")
    source = ROOT / "GreenBody-v2.blend"
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    params = {**DEFAULTS, **(json.loads(args.params.read_text()) if args.params else {})}
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    body = bpy.data.objects["GreenBody"]
    rig = next(m.object for m in body.modifiers if m.type == "ARMATURE")
    refinements = {}
    if params.get("head_refinement"):
        # The dedicated head module replaces these earlier trial strokes.
        params["face_relief"] = params["neck_polish"] = 0.0
    polish(body, params)
    if params.get("head_refinement"):
        from head_polish_v3 import refine_head
        refinements["head"] = refine_head(body, params.get("head_parameters"))
    if params.get("lower_refinement"):
        from lower_geometry_v3 import refine_lower
        refinements["lower"] = refine_lower(body, rig, params.get("lower_parameters"))
    _rotate(rig.pose.bones["root"], Quaternion((0, 0, 1), math.radians(params["body_yaw"])))
    if args.stance:
        from stance_v3 import apply_stance, plant_feet
        params["stance"] = apply_stance(rig, params.get("stance"))
        params["foot_contact"] = plant_feet(body, rig)
    upper_pose(rig, params)
    scene = bpy.context.scene
    scene.cycles.device = "CPU"
    scene["version"] = "Green Body V3 — calibrated static appearance study"
    scene["approved_for_animation"] = False
    scene["v3_parameters"] = json.dumps(params, sort_keys=True)
    scene["v3_parent_sha256"] = before
    body["status"] = "V3: actual sculpt and articulated stance; not integrated into iOS"
    from validate_green_body import check_original_mesh, check_armature_weights
    validation = {"errors": [], "warnings": []}
    check_original_mesh(body, validation)
    check_armature_weights(body, validation)
    assert not validation["errors"], validation["errors"]
    assert validation["original_mesh"]["connected_component_count"] == 1
    assert validation["original_mesh"]["nonmanifold_edge_count_including_boundary_and_wire"] == 0
    destination.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(destination))
    assert hashlib.sha256(source.read_bytes()).hexdigest() == before
    validation.update({"parameters": params, "source_sha256": before, "source_unchanged": True,
                       "refinements": refinements,
                       "candidate": str(destination), "candidate_sha256": hashlib.sha256(destination.read_bytes()).hexdigest()})
    destination.with_suffix(".json").write_text(json.dumps(validation, indent=2))
    print("V3_CANDIDATE", destination, flush=True)


if __name__ == "__main__":
    main()
