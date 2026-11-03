"""Small, symmetric REST-space calf and instep sculpt for Green Body V3.

No topology, bone, joint, weight or calibration edits. The underside of each
foot is protected; support is checked against the actual evaluated mesh after
the independent review stance is applied.
"""

import argparse
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from build_green_body import smoothstep

DEFAULTS = {"calf_volume": 0.10, "forefoot_width": 0.10,
            "instep_height": 0.007, "calf_center": 0.34, "calf_span": 0.23}


def gaussian(value, center, width):
    return math.exp(-0.5 * ((value - center) / width) ** 2)


def refine_lower(body, rig, params=None):
    """Apply symmetric local-volume edits to the stored, unposed mesh.

    Mesh coordinates remain in REST space even when the loaded V2 rig has its
    review pose. Calf changes are radial only; foot changes are transverse and
    dorsal. No longitudinal resizing or sole flattening is performed.
    """
    options = {**DEFAULTS, **(params or {})}
    for name, bound in (("calf_volume", .15), ("forefoot_width", .15),
                        ("instep_height", .012)):
        if not 0 <= options[name] <= bound:
            raise ValueError(f"{name} outside the bounded local-sculpt range")
    mesh = body.data
    changed = set()
    maximum_delta = 0.0
    for side, sign in (("L", 1), ("R", -1)):
        knee = rig.data.bones["lowerleg01." + side].head_local.copy()
        ankle = rig.data.bones["foot." + side].head_local.copy()
        shin = ankle - knee
        ball = sum((rig.data.bones[f"toe{toe}-1.{side}"].head_local
                    for toe in (2, 3, 4)), Vector()) / 3
        forward = ball - ankle
        forward.z = 0
        forward.normalize()
        across = Vector((-forward.y, forward.x, 0))
        for vertex in mesh.vertices:
            original = vertex.co.copy()
            x, y, z = original
            if sign * x < .045 or z > .55:
                continue
            offset = original - knee
            t = offset.dot(shin) / shin.length_squared
            radial = offset - shin * t
            if .035 < t < .94 and radial.length < .095:
                weight = gaussian(t, options["calf_center"], options["calf_span"])
                weight *= smoothstep(.035, .14, t) * (1-smoothstep(.76, .94, t))
                weight *= 1-smoothstep(.065, .095, radial.length)
                vertex.co += radial * options["calf_volume"] * weight
            foot_offset = original - ankle
            length = foot_offset.dot(forward)
            width = foot_offset.dot(across)
            if -.03 < length < .23 and abs(width) < .085 and z < .13:
                forefoot = smoothstep(.025, .075, length) * (1-smoothstep(.17, .23, length))
                forefoot *= 1-smoothstep(.055, .085, abs(width))
                vertex.co += across * width * options["forefoot_width"] * forefoot
                top = smoothstep(.017, .043, z) * (1-smoothstep(.105, .13, z))
                instep = gaussian(length, .065, .041) * gaussian(width, 0, .035)
                vertex.co.z += options["instep_height"] * top * instep
            displacement = (vertex.co - original).length
            if displacement > 1e-8:
                changed.add(vertex.index)
                maximum_delta = max(maximum_delta, displacement)
    mesh.update()
    result = {"parameters": options, "changed_vertices": len(changed),
              "maximum_displacement_m": maximum_delta,
              "symmetry": "Same scalar profile on each anatomical leg and foot",
              "bone_lengths_changed": False, "topology_changed": False,
              "weights_changed": False, "surface_type": "Local radial calf / transverse forefoot / dorsal instep sculpt"}
    body["v3_lower_geometry"] = json.dumps(result, sort_keys=True)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--name", required=True)
    parser.add_argument("--params", default="{}")
    parser.add_argument("--views", nargs="*", default=[], choices=["Front", "Side", "Back"])
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    if not args.name.replace("-", "").replace("_", "").isalnum():
        raise ValueError("Use a short file-safe experiment name")
    out = ROOT / "renders" / "v3-lower-experiments" / args.name
    out.mkdir(parents=True, exist_ok=False)
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / "GreenBody-v2.blend"), use_scripts=False)
    body = bpy.data.objects["GreenBody"]
    rig = bpy.data.objects["GB_ReviewArmature"]
    result = refine_lower(body, rig, json.loads(args.params))
    from stance_v3 import apply_stance, plant_feet
    result["stance"] = apply_stance(rig)
    result["support"] = plant_feet(body, rig)
    from validate_green_body import check_original_mesh, check_armature_weights
    result.update({"errors": [], "warnings": []})
    check_original_mesh(body, result)
    check_armature_weights(body, result)
    assert not result["errors"], result["errors"]
    (out / "lower.json").write_text(json.dumps(result, indent=2) + "\n")
    bpy.context.scene["version"] = "V3 lower-body experiment " + args.name
    bpy.ops.wm.save_as_mainfile(filepath=str(out / "candidate.blend"))
    print("LOWER_EXPERIMENT", str(out / "candidate.blend"), flush=True)
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
