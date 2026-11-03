"""Local upper-leg X cross-section refinement from V47.

V47's fixed-protocol front/back residual shows slightly under-wide thighs while
the side projection is already close.  This is a real rest-surface volume
change around each femur centreline, not camera-facing geometry.
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


def digest(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def smooth(a, b, x):
    t = max(0.0, min(1.0, (x-a)/(b-a)))
    return t*t*(3-2*t)


def main():
    assert bpy.app.background
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=ROOT / "GreenBody-v47-work.blend")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--width", type=float, default=.04)
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    assert 0 < args.width <= .10
    source, out = args.source.resolve(), args.out.resolve()
    assert not out.exists() and not out.with_suffix(".json").exists()
    before = digest(source)
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    body, rig, mesh = bpy.data.objects["GreenBody"], bpy.data.objects["GB_ReviewArmature"], bpy.data.objects["GreenBody"].data
    original = [v.co.copy() for v in mesh.vertices]
    shapes = {key.name: [p.co.copy() for p in key.data] for key in mesh.shape_keys.key_blocks}
    weights = [tuple((g.group, g.weight) for g in v.groups) for v in mesh.vertices]
    groups, centres = {}, {}
    for side in ("L", "R"):
        names = {f"upperleg01.{side}", f"upperleg02.{side}"}
        groups[side] = {g.index for g in body.vertex_groups if g.name in names}
        hip = rig.data.bones[f"upperleg01.{side}"].head_local
        knee = rig.data.bones[f"lowerleg01.{side}"].head_local
        centres[side] = (hip, knee)
    delta = []
    for co, row in zip(original, weights):
        d = Vector()
        for side in ("L", "R"):
            influence = sum(w for group, w in row if group in groups[side])
            hip, knee = centres[side]
            # Preserve the hip crease and knee fold; the volume peak is in the
            # muscular mid-thigh and fades continuously into both joints.
            band = smooth(.57, .68, co.z) * (1-smooth(.88, .99, co.z))
            if influence and band:
                t = max(0.0, min(1.0, (co.z-knee.z)/max(1e-7, hip.z-knee.z)))
                centre_x = knee.x*(1-t)+hip.x*t
                d.x += (co.x-centre_x)*args.width*band*influence
        delta.append(d)
    for vertex, d in zip(mesh.vertices, delta): vertex.co += d
    for key in mesh.shape_keys.key_blocks:
        for i, point in enumerate(key.data): point.co = shapes[key.name][i]+delta[i]
    mesh.update(); bpy.context.view_layer.update()
    basis = mesh.shape_keys.key_blocks["Basis"]
    relative_error = max(((p.co-basis.data[i].co)-(shapes[key.name][i]-shapes["Basis"][i])).length
                         for key in mesh.shape_keys.key_blocks for i,p in enumerate(key.data))
    assert relative_error < 1e-6
    assert weights == [tuple((g.group, g.weight) for g in v.groups) for v in mesh.vertices]
    assert all(c.driver.is_valid for c in mesh.shape_keys.animation_data.drivers)
    report = {"errors": [], "warnings": [], "source": str(source), "source_sha256": before,
              "thigh_x_expansion_fraction": args.width,
              "changed_vertices": sum(d.length > 1e-8 for d in delta),
              "maximum_displacement_m": max(d.length for d in delta),
              "relative_key_error_m": relative_error, "weights_unchanged": True,
              "scope": "X-only upper-leg rest-surface expansion, copied identically to relative keys; rig, pose, cameras, material and scoring unchanged."}
    check_original_mesh(body, report); check_armature_weights(body, report)
    assert not report["errors"], report["errors"]
    assert report["original_mesh"]["connected_component_count"] == 1
    assert report["original_mesh"]["nonmanifold_edge_count_including_boundary_and_wire"] == 0
    bpy.context.scene["version"] = "V48 local thigh X cross-section study"
    bpy.context.scene["approved_for_animation"] = False
    bpy.context.scene.cycles.device = "CPU"
    out.parent.mkdir(parents=True, exist_ok=True); bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert digest(source) == before
    report.update(candidate=str(out), candidate_sha256=digest(out), source_unchanged=True,
                  builder_sha256=digest(__file__))
    out.with_suffix(".json").write_text(json.dumps(report, indent=2))
    print("V48_CANDIDATE", out, flush=True)


if __name__ == "__main__": main()
