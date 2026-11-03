"""Medial calf contour study, unchanged bones/pose and corrective deltas."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_green_body import smoothstep
from validate_green_body import check_original_mesh, check_armature_weights


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    assert bpy.app.background
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=ROOT / 'GreenBody-v15.1-work.blend')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--amount', type=float, default=.018)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    assert 0 <= args.amount <= .025
    source, out = args.source.resolve(), args.out.resolve()
    assert not out.exists() and not out.with_suffix('.json').exists()
    source_hash = digest(source)
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    body, rig = bpy.data.objects['GreenBody'], bpy.data.objects['GB_ReviewArmature']
    original = [v.co.copy() for v in body.data.vertices]
    shapes = {key.name: [p.co.copy() for p in key.data] for key in body.data.shape_keys.key_blocks}
    weights = [tuple((g.group, g.weight) for g in v.groups) for v in body.data.vertices]
    delta = [Vector() for _ in original]
    counts = {}
    for side, sign in [('L', 1), ('R', -1)]:
        start = rig.data.bones['lowerleg01.' + side].head_local
        end = rig.data.bones['foot.' + side].head_local
        axis = end - start
        unit = axis.normalized()
        medial = Vector((-sign, 0, 0))
        medial = (medial - unit * medial.dot(unit)).normalized()
        groups = {g.index for g in body.vertex_groups
                  if g.name.startswith('lowerleg') and g.name.endswith('.' + side)}
        counts[side] = 0
        for i, co in enumerate(original):
            vec = co - start
            t = vec.dot(axis) / axis.length_squared
            radius = (vec - axis * t).length
            weight = sum(w for g, w in weights[i] if g in groups)
            if not .04 < t < .96 or radius >= .13 or weight <= .1:
                continue
            envelope = math.sin(math.pi * (t - .04) / .92) ** 2
            envelope *= smoothstep(.1, .8, weight) * (1 - smoothstep(.10, .13, radius))
            delta[i] = medial * (args.amount * envelope)
            counts[side] += 1
    for i, vertex in enumerate(body.data.vertices):
        vertex.co = original[i] + delta[i]
    for key in body.data.shape_keys.key_blocks:
        for i, point in enumerate(key.data):
            point.co = shapes[key.name][i] + delta[i]
    body.data.update()
    bpy.context.view_layer.update()
    basis = body.data.shape_keys.key_blocks['Basis']
    error = max(((point.co - basis.data[i].co) -
                 (shapes[key.name][i] - shapes['Basis'][i])).length
                for key in body.data.shape_keys.key_blocks for i, point in enumerate(key.data))
    assert error < 1e-6
    assert weights == [tuple((g.group, g.weight) for g in v.groups) for v in body.data.vertices]
    report = {'errors': [], 'warnings': [], 'amount_m': args.amount, 'changed_vertices': counts,
              'max_displacement_m': max(d.length for d in delta), 'shape_delta_error_m': error,
              'weights_and_rig_unchanged': True, 'source': str(source), 'source_sha256': source_hash}
    check_original_mesh(body, report)
    check_armature_weights(body, report)
    assert not report['errors'], report['errors']
    assert report['original_mesh']['connected_component_count'] == 1
    assert report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire'] == 0
    assert all(c.driver.is_valid for c in body.data.shape_keys.animation_data.drivers)
    bpy.context.scene['version'] = 'V17 medial calf contour study'
    bpy.context.scene['approved_for_animation'] = False
    bpy.context.scene.cycles.device = 'CPU'
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert digest(source) == source_hash
    report.update(candidate=str(out), candidate_sha256=digest(out), source_unchanged=True,
                  builder_sha256=digest(__file__))
    out.with_suffix('.json').write_text(json.dumps(report, indent=2))
    print('V17_CANDIDATE', out, flush=True)


if __name__ == '__main__':
    main()
