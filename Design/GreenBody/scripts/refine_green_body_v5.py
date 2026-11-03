"""Bounded anatomical surface studies on V4; actual mesh edits, no image fitting.

The CC0 source head supplies restrained surface planes. The closed V4 topology,
skin weights, posing, studio and calibration protocol are left intact.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from build_green_body import smoothstep
from validate_green_body import check_original_mesh, check_armature_weights


def raw_head():
    """Same project coordinate convention, before the original blank-face morph."""
    coordinates, faces, group = [], [], None
    with (ROOT / "source/makehuman-base.obj").open() as stream:
        for line in stream:
            bits = line.split()
            if not bits:
                continue
            if bits[0] == "v":
                coordinates.append(Vector(tuple(map(float, bits[1:4]))))
            elif bits[0] == "g":
                group = bits[1]
            elif bits[0] == "f" and group == "body":
                faces.append(tuple(int(item.split("/")[0]) - 1 for item in bits[1:]))
    assert len(coordinates) == 19158 and len(faces) == 13378
    for name, influence in [("adult-male.target", 1), ("lean-tone.target", .22),
                            ("ideal-proportions.target", .38),
                            ("eye-left-closure.target", 1), ("eye-right-closure.target", 1),
                            ("nose-scale-depth-decr.target", .55),
                            ("mouth-upperlip-volume-decr.target", .75),
                            ("mouth-lowerlip-volume-decr.target", .75),
                            ("l-ear-scale-decr.target", .4), ("r-ear-scale-decr.target", .4)]:
        with (ROOT / "source" / name).open() as stream:
            for line in stream:
                bits = line.split()
                if len(bits) == 4 and not bits[0].startswith("#"):
                    coordinates[int(bits[0])] += Vector(tuple(map(float, bits[1:]))) * influence
    points = [Vector((p.x * .1, -p.z * .1, p.y * .1)) for p in coordinates]
    used = sorted({i for face in faces for i in face})
    floor = min(points[i].z for i in used)
    scale = 1.82 / (max(points[i].z for i in used) - floor)
    for p in points:
        p.z -= floor
        p *= scale
        w = smoothstep(1.56, 1.66, p.z)
        p.x *= .92 * (1 + .09 * w)
        p.y *= .96 * (1 + .05 * w)
        p.z += .085 * w * (p.z - 1.56)
    scale = 1.82 / max(points[i].z for i in used)
    points = [p * scale for p in points]
    head_faces = [f for f in faces if all(points[i].z > 1.55 for i in f)]
    return BVHTree.FromPolygons(points, head_faces, all_triangles=False)


def refine_head(body, strength, polish):
    mesh = body.data
    original = [v.co.copy() for v in mesh.vertices]
    weights = [tuple((g.group, g.weight) for g in v.groups) for v in mesh.vertices]
    bvh = raw_head()
    targets, influence, neighbors = {}, {}, [[] for _ in mesh.vertices]
    for edge in mesh.edges:
        a, b = edge.vertices
        neighbors[a].append(b)
        neighbors[b].append(a)
    for v in mesh.vertices:
        x, y, z = v.co
        if not (1.60 < z < 1.765 and y < -.035 and abs(x) < .081):
            continue
        hit, _, _, _ = bvh.ray_cast(Vector((x, -.35, z)), Vector((0, 1, 0)), .35)
        if hit is None:
            continue
        targets[v.index] = max(-.025, min(.025, hit.y - y))
        influence[v.index] = (smoothstep(1.60, 1.626, z)
                              * (1-smoothstep(1.73, 1.765, z))
                              * (1-smoothstep(.054, .081, abs(x)))
                              * (1-smoothstep(-.075, -.035, y)))
    # Filter only the transferred displacement, not the existing geometry.
    # This suppresses source eyelid/lip grooves without shrinking the skull.
    for _ in range(18):
        previous = targets.copy()
        for i in targets:
            valid = [j for j in neighbors[i] if j in previous]
            if valid:
                targets[i] = previous[i] * .55 + .45 * sum(previous[j] for j in valid) / len(valid)
    for i, delta in targets.items():
        mesh.vertices[i].co.y += delta * influence[i] * strength
    # Light tangential seam polish on the posterior cranium only. Front planes
    # and the ear are outside this bounded brush; no silhouette-target fitting.
    for _ in range(12):
        previous = [v.co.copy() for v in mesh.vertices]
        for v in mesh.vertices:
            x, y, z = original[v.index]
            w = smoothstep(-.015, .025, y) * smoothstep(1.63, 1.68, z)
            w *= (1-smoothstep(1.74, 1.78, z)) * (1-smoothstep(.05, .075, abs(x)))
            if w > 0 and neighbors[v.index]:
                avg = sum((previous[j] for j in neighbors[v.index]), Vector()) / len(neighbors[v.index])
                v.co += (avg-previous[v.index]) * w * .3 * polish
    mesh.update()
    assert all(tuple(v.co) == tuple(original[v.index]) for v in mesh.vertices if original[v.index].z <= 1.6)
    assert weights == [tuple((g.group, g.weight) for g in v.groups) for v in mesh.vertices]
    return {"sampled_vertices": len(targets), "changed_vertices": sum(v.co != original[v.index] for v in mesh.vertices),
            "max_displacement_m": max((v.co-original[v.index]).length for v in mesh.vertices),
            "weights_preserved": True, "below_1_6_m_unchanged": True}


def main():
    assert bpy.app.background, "Background process only"
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=ROOT / "GreenBody-v4-work.blend")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--strength", type=float, default=.5)
    parser.add_argument("--polish", type=float, default=1)
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    if not all(math.isfinite(v) and 0 <= v <= 1 for v in (args.strength, args.polish)):
        raise ValueError("Strength/polish must be finite within [0,1]")
    out, source = args.out.resolve(), args.source.resolve()
    if out.exists() or out.with_suffix('.json').exists():
        raise ValueError("Refusing to overwrite existing model/evidence")
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    body = bpy.data.objects['GreenBody']
    report = {"parameters": {"strength": args.strength, "polish": args.polish},
              "geometry": refine_head(body, args.strength, args.polish), "errors": [], "warnings": []}
    check_original_mesh(body, report)
    check_armature_weights(body, report)
    assert not report['errors'], report['errors']
    assert report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire'] == 0
    assert report['original_mesh']['connected_component_count'] == 1
    scene = bpy.context.scene
    scene['version'] = 'Green Body V5 anatomical head study'
    scene['approved_for_animation'] = False
    scene['v5_parameters'] = json.dumps(report['parameters'], sort_keys=True)
    scene['v5_builder_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    scene.cycles.device = 'CPU'
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert hashlib.sha256(source.read_bytes()).hexdigest() == digest
    report.update({"source": str(source), "source_sha256": digest, "source_unchanged": True,
                   "candidate": str(out), "candidate_sha256": hashlib.sha256(out.read_bytes()).hexdigest()})
    out.with_suffix('.json').write_text(json.dumps(report, indent=2))
    print('V5_HEAD_CANDIDATE', out, flush=True)


if __name__ == '__main__':
    main()
