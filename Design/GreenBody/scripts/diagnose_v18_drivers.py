"""Read-only comparison of original/evaluated driver values after rest-rig edits."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import bpy
from mathutils import Matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_green_body_v14 import expected
from prepare_turnaround_pose_v2 import canonical_pose
from review_poses import reset, update
from review_poses_v2 import deep_squat, low_push_up


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--blend', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    assert not args.out.exists()
    source = args.blend.resolve()
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    body, rig = bpy.data.objects['GreenBody'], bpy.data.objects['GB_ReviewArmature']
    canonical_pose(body, rig)
    original = {b.name: b.matrix_basis.copy() for b in rig.pose.bones}
    rows = []
    for name, fn in [('squat', deep_squat), ('push-up', low_push_up)]:
        reset(rig)
        fn(rig)
        target = {b.name: b.matrix_basis.copy() for b in rig.pose.bones}
        for index in range(41):
            t = index / 40
            for b in rig.pose.bones:
                a, ar, asc = original[b.name].decompose()
                z, zr, zsc = target[b.name].decompose()
                b.matrix_basis = Matrix.LocRotScale(a.lerp(z, t), ar.slerp(zr, t), asc.lerp(zsc, t))
            update()
            dg = bpy.context.evaluated_depsgraph_get()
            keys = body.data.shape_keys
            evaluated = keys.evaluated_get(dg)
            for side in ('L', 'R'):
                keyname = 'GB_Trapezius_PoseFill_' + side
                want, distances = expected(rig, side)
                eval_want, _ = expected(rig.evaluated_get(dg), side)
                rows.append(dict(pose=name, t=t, side=side, original=float(keys.key_blocks[keyname].value),
                                 evaluated=float(evaluated.key_blocks[keyname].value), expected=want,
                                 evaluated_expected=eval_want, distances=distances))
    assert hashlib.sha256(source.read_bytes()).hexdigest() == before
    result = {'source': str(source), 'source_sha256': before, 'rows': rows,
              'max_original_error': max(abs(r['original'] - r['expected']) for r in rows),
              'max_evaluated_error': max(abs(r['evaluated'] - r['evaluated_expected']) for r in rows)}
    args.out.write_text(json.dumps(result, indent=2))
    print(json.dumps({k: v for k, v in result.items() if k != 'rows'}))
    print('WORST', json.dumps(max(rows, key=lambda r: abs(r['evaluated'] - r['evaluated_expected']))))


if __name__ == '__main__':
    main()
