"""Forefoot thickness and heel volume study with soles/rig/keys preserved."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_green_body import smoothstep
from validate_green_body import check_original_mesh, check_armature_weights


def digest(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main():
    assert bpy.app.background
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=ROOT / 'GreenBody-v18-work.blend')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--dorsum', type=float, default=.018)
    parser.add_argument('--heel', type=float, default=.014)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    assert 0 <= args.dorsum <= .03 and 0 <= args.heel <= .025
    source, out = args.source.resolve(), args.out.resolve()
    assert not out.exists() and not out.with_suffix('.json').exists()
    source_hash = digest(source)
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    body, rig = bpy.data.objects['GreenBody'], bpy.data.objects['GB_ReviewArmature']
    original = [v.co.copy() for v in body.data.vertices]
    shapes = {k.name: [p.co.copy() for p in k.data] for k in body.data.shape_keys.key_blocks}
    weights = [tuple((g.group, g.weight) for g in v.groups) for v in body.data.vertices]
    delta = [Vector() for _ in original]
    counts = {}
    for side, sign in [('L', 1), ('R', -1)]:
        anchor = rig.data.bones['foot.' + side].head_local
        foot_names = {b.name for b in [rig.data.bones['foot.' + side], *rig.data.bones['foot.' + side].children_recursive]}
        groups = {g.index for g in body.vertex_groups if g.name in foot_names}
        counts[side] = 0
        for i, co in enumerate(original):
            if sign * co.x < .035 or not .008 < co.z < .16:
                continue
            weight = sum(w for g, w in weights[i] if g in groups)
            mask = smoothstep(.1, .8, weight)
            if not mask:
                continue
            forward = anchor.y - co.y
            lift = args.dorsum * smoothstep(.04, .14, forward)
            lift *= smoothstep(.012, .043, co.z) * (1-smoothstep(.10, .15, co.z))
            heel = args.heel * smoothstep(-.018, .035, co.y-anchor.y)
            heel *= smoothstep(.008, .035, co.z) * (1-smoothstep(.09, .16, co.z))
            delta[i] = Vector((0, mask*heel, mask*lift))
            counts[side] += int(delta[i].length > 1e-8)
    for i, v in enumerate(body.data.vertices):
        v.co = original[i] + delta[i]
    for key in body.data.shape_keys.key_blocks:
        for i, point in enumerate(key.data):
            point.co = shapes[key.name][i] + delta[i]
    body.data.update()
    bpy.context.view_layer.update()
    basis = body.data.shape_keys.key_blocks['Basis']
    error = max(((p.co-basis.data[i].co)-(shapes[k.name][i]-shapes['Basis'][i])).length
                for k in body.data.shape_keys.key_blocks for i, p in enumerate(k.data))
    assert error < 1e-6
    assert all(d.length == 0 for d, co in zip(delta, original) if co.z <= .008 or co.z >= .16)
    assert all(d.x == 0 for d in delta)
    assert weights == [tuple((g.group, g.weight) for g in v.groups) for v in body.data.vertices]
    report = {'errors': [], 'warnings': [], 'dorsum_m': args.dorsum, 'heel_m': args.heel,
              'changed_vertices': counts, 'maximum_displacement_m': max(d.length for d in delta),
              'shape_delta_error_m': error, 'sole_and_upper_body_unchanged': True,
              'weights_and_rig_unchanged': True, 'source': str(source), 'source_sha256': source_hash}
    check_original_mesh(body, report)
    check_armature_weights(body, report)
    assert not report['errors'], report['errors']
    assert report['original_mesh']['connected_component_count'] == 1
    assert report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire'] == 0
    assert all(c.driver.is_valid for c in body.data.shape_keys.animation_data.drivers)
    bpy.context.scene['version'] = 'V20 forefoot thickness and heel-volume study'
    bpy.context.scene['approved_for_animation'] = False
    bpy.context.scene.cycles.device = 'CPU'
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert digest(source) == source_hash
    report.update(candidate=str(out), candidate_sha256=digest(out), source_unchanged=True,
                  builder_sha256=digest(__file__))
    out.with_suffix('.json').write_text(json.dumps(report, indent=2))
    print('V20_CANDIDATE', out, flush=True)


if __name__ == '__main__':
    main()
