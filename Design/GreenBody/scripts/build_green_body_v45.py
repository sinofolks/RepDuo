"""Local ankle cross-section refinement from V40.

The v4 reference comparison isolates excessive frontal ankle width while side
depth is already close.  This makes a small X-only, rest-space taper around
each lower-leg bone centre.  It is deliberately separate from the old broad
shin/hip experiment: no hip, knee, foot sole, bone, pose, camera or material
state is altered.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from validate_green_body import check_armature_weights, check_original_mesh


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def main():
    assert bpy.app.background
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=ROOT / "GreenBody-v40-work.blend")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--taper", type=float, default=.06)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    assert 0.0 < args.taper <= .10
    source, out = args.source.resolve(), args.out.resolve()
    assert not out.exists() and not out.with_suffix(".json").exists()
    source_hash = digest(source)

    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    body = bpy.data.objects["GreenBody"]
    rig = bpy.data.objects["GB_ReviewArmature"]
    mesh = body.data
    original = [v.co.copy() for v in mesh.vertices]
    shapes = {key.name: [point.co.copy() for point in key.data] for key in mesh.shape_keys.key_blocks}
    weights = [tuple((group.group, group.weight) for group in vertex.groups) for vertex in mesh.vertices]
    lower_groups = {}
    centres = {}
    for side in ("L", "R"):
        names = {f"lowerleg01.{side}", f"lowerleg02.{side}"}
        lower_groups[side] = {group.index for group in body.vertex_groups if group.name in names}
        knee = rig.data.bones[f"lowerleg01.{side}"].head_local
        ankle = rig.data.bones[f"foot.{side}"].head_local
        centres[side] = (knee, ankle)

    delta = []
    for co, row in zip(original, weights):
        displacement = Vector()
        for side in ("L", "R"):
            influence = sum(weight for group, weight in row if group in lower_groups[side])
            knee, ankle = centres[side]
            # Taper only the lower calf/ankle; it fades before the knee and
            # before the foot sole so stance contacts and toe proportions stay
            # unchanged.  The local bone centre avoids pulling both legs inward.
            band = smooth(.12, .25, co.z) * (1.0 - smooth(.43, .53, co.z))
            if not influence or not band:
                continue
            axis_t = max(0.0, min(1.0, (co.z - ankle.z) / max(1e-7, knee.z - ankle.z)))
            centre_x = ankle.x * (1.0 - axis_t) + knee.x * axis_t
            displacement.x += (centre_x - co.x) * args.taper * band * influence
        delta.append(displacement)

    for vertex, displacement in zip(mesh.vertices, delta):
        vertex.co += displacement
    for key in mesh.shape_keys.key_blocks:
        for index, point in enumerate(key.data):
            point.co = shapes[key.name][index] + delta[index]
    mesh.update()
    bpy.context.view_layer.update()
    basis = mesh.shape_keys.key_blocks["Basis"]
    relative_error = max(
        ((point.co - basis.data[index].co) - (shapes[key.name][index] - shapes["Basis"][index])).length
        for key in mesh.shape_keys.key_blocks for index, point in enumerate(key.data)
    )
    assert relative_error < 1e-6
    assert weights == [tuple((group.group, group.weight) for group in vertex.groups) for vertex in mesh.vertices]
    assert all(curve.driver.is_valid for curve in mesh.shape_keys.animation_data.drivers)
    report = {
        "errors": [], "warnings": [], "source": str(source), "source_sha256": source_hash,
        "ankle_x_taper_fraction": args.taper,
        "changed_vertices": sum(displacement.length > 1e-8 for displacement in delta),
        "maximum_displacement_m": max(displacement.length for displacement in delta),
        "relative_key_error_m": relative_error, "weights_unchanged": True,
        "scope": "X-only lower-leg rest-surface taper; all shape keys receive the identical displacement. Rig, feet, pose, cameras, material and scoring unchanged.",
    }
    check_original_mesh(body, report)
    check_armature_weights(body, report)
    assert not report["errors"], report["errors"]
    assert report["original_mesh"]["connected_component_count"] == 1
    assert report["original_mesh"]["nonmanifold_edge_count_including_boundary_and_wire"] == 0
    bpy.context.scene["version"] = "V45 local ankle cross-section study"
    bpy.context.scene["approved_for_animation"] = False
    bpy.context.scene.cycles.device = "CPU"
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert digest(source) == source_hash
    report.update(candidate=str(out), candidate_sha256=digest(out), source_unchanged=True,
                  builder_sha256=digest(__file__))
    out.with_suffix(".json").write_text(json.dumps(report, indent=2))
    print("V45_CANDIDATE", out, flush=True)


if __name__ == "__main__":
    main()
