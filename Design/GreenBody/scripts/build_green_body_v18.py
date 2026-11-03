"""Actual bilateral arm proportion changes with matching skin/rest-rig edits.

Fixed capture pose remains v2. Shoulder segment widens; upper/lower arm
segments lengthen axially. Hands translate rigidly, never scale up.
"""
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
from prepare_turnaround_pose_v2 import canonical_pose
from validate_green_body import check_original_mesh, check_armature_weights


def digest(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main():
    assert bpy.app.background
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=ROOT / 'GreenBody-v17.1-work.blend')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--width', type=float, default=.012)
    parser.add_argument('--length', type=float, default=.04)
    parser.add_argument('--upperarm-undo', type=float, default=0.)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    assert 0 <= args.width <= .025 and 0 <= args.length <= .08
    assert 0 <= args.upperarm_undo <= 1
    source, out = args.source.resolve(), args.out.resolve()
    assert not out.exists() and not out.with_suffix('.json').exists()
    source_hash = digest(source)
    upperarm_delta, reversal_sources = None, {}
    if args.upperarm_undo:
        snapshots = []
        for name in ('GreenBody-v14-work.blend', 'GreenBody-v15.1-work.blend'):
            path = ROOT / name
            reversal_sources[str(path)] = digest(path)
            bpy.ops.wm.open_mainfile(filepath=str(path), use_scripts=False)
            obj = bpy.data.objects['GreenBody']
            snapshots.append([v.co.copy() for v in obj.data.vertices])
        assert len(snapshots[0]) == len(snapshots[1])
        upperarm_delta = [b-a for a,b in zip(*snapshots)]
        assert max(d.length for d in upperarm_delta) < .01601
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    body, rig = bpy.data.objects['GreenBody'], bpy.data.objects['GB_ReviewArmature']
    # Keep the analytical driver output unchanged by an implicit Bezier
    # transfer curve. A native identity generator has no endpoint snapping.
    transfer_checks = []
    for curve in body.data.shape_keys.animation_data.drivers:
        assert not curve.modifiers
        assert [tuple(k.co) for k in curve.keyframe_points] == [(0., 0.), (1., 1.)]
        samples = [0., .2, .5, .8, .9999157444471376, 1.]
        before_transfer = [curve.evaluate(x) for x in samples]
        curve.keyframe_points.clear()
        generator = curve.modifiers.new('GENERATOR')
        generator.mode = 'POLYNOMIAL'
        generator.poly_order = 1
        generator.coefficients = (0., 1.)
        curve.update()
        after_transfer = [curve.evaluate(x) for x in samples]
        assert max(abs(x-y) for x,y in zip(samples, after_transfer)) < 1e-6
        transfer_checks.append(dict(path=curve.data_path, inputs=samples,
                                    before=before_transfer, after=after_transfer))
    original = [v.co.copy() for v in body.data.vertices]
    shapes = {k.name: [p.co.copy() for p in k.data] for k in body.data.shape_keys.key_blocks}
    weights = [tuple((g.group, g.weight) for g in v.groups) for v in body.data.vertices]
    bones = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in rig.data.bones}
    hand_names = {b.name for side in ('L', 'R')
                  for b in [rig.data.bones['wrist.' + side],
                            *rig.data.bones['wrist.' + side].children_recursive]}
    for side in ('L', 'R'):
        assert all(b.name in hand_names or b.name.startswith(('upperarm', 'lowerarm'))
                   for b in rig.data.bones['upperarm01.' + side].children_recursive)
    params = {}
    for side, sign in [('L', 1), ('R', -1)]:
        shoulder = bones['upperarm01.' + side][0]
        elbow = bones['lowerarm01.' + side][0]
        wrist = bones['wrist.' + side][0]
        params[side] = (shoulder, elbow, wrist, Vector((sign * args.width, 0, 0)))

    def displacement(name, co):
        side = name[-1:]
        if side not in params or not name.endswith('.' + side):
            return Vector()
        shoulder, elbow, wrist, widening = params[side]
        upper, lower = elbow - shoulder, wrist - elbow
        if name.startswith('shoulder'):
            start = bones['shoulder01.' + side][0]
            axis = shoulder - start
            t = (co - start).dot(axis) / axis.length_squared
            return widening * smoothstep(0, 1, t)
        if name.startswith('upperarm'):
            t = min(1, max(0, (co - shoulder).dot(upper) / upper.length_squared))
            return widening + args.length * t * upper
        if name.startswith('lowerarm'):
            t = min(1, max(0, (co - elbow).dot(lower) / lower.length_squared))
            return widening + args.length * (upper + t * lower)
        if name in hand_names:
            return widening + args.length * (upper + lower)
        return Vector()

    restored = [co - (upperarm_delta[i] * args.upperarm_undo if upperarm_delta else Vector())
                for i,co in enumerate(original)]
    delta = [restored[i]-original[i]+sum((displacement(body.vertex_groups[g].name, co) * w
                  for g, w in weights[i]), Vector()) for i, co in enumerate(restored)]
    for i, vertex in enumerate(body.data.vertices):
        vertex.co = original[i] + delta[i]
    for key in body.data.shape_keys.key_blocks:
        for i, point in enumerate(key.data):
            point.co = shapes[key.name][i] + delta[i]
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for bone in rig.data.edit_bones:
        a, b = bones[bone.name]
        bone.head, bone.tail = a + displacement(bone.name, a), b + displacement(bone.name, b)
    bpy.ops.object.mode_set(mode='OBJECT')
    # Every palm/finger bone must undergo the same rigid translation. Checking
    # descendants catches overlooked metacarpals, not just finger-name matches.
    for name in hand_names:
        side = name[-1]
        a, b = bones[name]
        shift = displacement(name, a)
        assert (rig.data.bones[name].head_local - a - shift).length < 1e-6
        assert (rig.data.bones[name].tail_local - b - shift).length < 1e-6
    body.data.update()
    bpy.context.view_layer.update()
    basis = body.data.shape_keys.key_blocks['Basis']
    error = max(((p.co - basis.data[i].co) - (shapes[k.name][i] - shapes['Basis'][i])).length
                for k in body.data.shape_keys.key_blocks for i, p in enumerate(k.data))
    assert error < 1e-6
    assert weights == [tuple((g.group, g.weight) for g in v.groups) for v in body.data.vertices]
    lengths = {}
    for side in params:
        a, b, c = [rig.data.bones[n + '.' + side].head_local for n in ('upperarm01', 'lowerarm01', 'wrist')]
        old_a, old_b, old_c, _ = params[side]
        ratios = [(b - a).length / (old_b - old_a).length, (c - b).length / (old_c - old_b).length]
        assert all(abs(r - 1 - args.length) < 1e-5 for r in ratios), ratios
        lengths[side] = ratios
    report = {'errors': [], 'warnings': [], 'width_per_side_m': args.width,
              'arm_length_fraction': args.length, 'arm_segment_ratios': lengths,
              'v15_upperarm_reversal_fraction': args.upperarm_undo,
              'upperarm_reversal_sources': reversal_sources,
              'changed_vertices': sum(d.length > 1e-8 for d in delta),
              'maximum_displacement_m': max(d.length for d in delta),
              'shape_delta_error_m': error, 'weights_unchanged': True,
              'all_hand_descendants_translate_rigidly': True,
              'driver_identity_transfer_checks': transfer_checks,
              'source': str(source), 'source_sha256': source_hash}
    check_original_mesh(body, report)
    check_armature_weights(body, report)
    assert not report['errors'], report['errors']
    assert report['original_mesh']['connected_component_count'] == 1
    assert report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire'] == 0
    report['support'] = canonical_pose(body, rig)
    assert all(c.driver.is_valid for c in body.data.shape_keys.animation_data.drivers)
    bpy.context.scene['version'] = 'V18 real shoulder width and arm-length study'
    bpy.context.scene['approved_for_animation'] = False
    bpy.context.scene.cycles.device = 'CPU'
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert digest(source) == source_hash
    assert all(digest(p) == h for p,h in reversal_sources.items())
    report.update(candidate=str(out), candidate_sha256=digest(out), source_unchanged=True,
                  builder_sha256=digest(__file__))
    out.with_suffix('.json').write_text(json.dumps(report, indent=2))
    print('V18_CANDIDATE', out, flush=True)


if __name__ == '__main__':
    main()
