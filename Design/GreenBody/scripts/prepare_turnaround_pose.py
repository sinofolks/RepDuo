"""Create a separate canonical-pose model for the approved turnaround.

Identical pose rule for every mesh version. No camera fitting or image changes.
Original mesh data, skin weights and source file are preserved.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
from review_poses import reset, aim_chain, set_world_rotation, rotate_world, update
from review_poses_v2 import evaluated_points
from validate_green_body import check_original_mesh, check_armature_weights


def canonical_pose(body, rig):
    reset(rig)
    for side, sign in (('L', 1), ('R', -1)):
        aim_chain(rig, 'upperleg01.'+side, 'lowerleg01.'+side, (sign*.14, 0, -1))
        aim_chain(rig, 'lowerleg01.'+side, 'foot.'+side, (sign*.14, 0, -1))
        foot = rig.pose.bones['foot.'+side]
        ball = sum((rig.data.bones[f'toe{n}-1.{side}'].head_local for n in (2,3,4)), Vector())/3
        forward = ball-foot.bone.head_local
        yaw = -math.atan2(forward.x, -forward.y)
        set_world_rotation(foot, Quaternion((0,0,1), yaw) @ foot.bone.matrix_local.to_quaternion())
        aim_chain(rig, 'upperarm01.'+side, 'lowerarm01.'+side,
                  (sign*math.sin(math.radians(18)), -.025, -math.cos(math.radians(18))))
        aim_chain(rig, 'lowerarm01.'+side, 'wrist.'+side,
                  (sign*math.sin(math.radians(12)), -.13, -math.cos(math.radians(12))))
        wrist = rig.pose.bones['wrist.'+side]
        forward = (rig.pose.bones['finger3-1.'+side].head-wrist.head).normalized()
        across = rig.pose.bones['finger2-1.'+side].head-rig.pose.bones['finger5-1.'+side].head
        across = (across-forward*across.dot(forward)).normalized()
        current = Matrix((across, forward, across.cross(forward))).transposed()
        desired_forward = Vector((sign*.025, -.08, -1)).normalized()
        desired_across = Vector((-sign, -.10, 0))
        desired_across = (desired_across-desired_forward*desired_across.dot(desired_forward)).normalized()
        target = Matrix((desired_across, desired_forward, desired_across.cross(desired_forward))).transposed()
        rotate_world(wrist, target @ current.transposed())
        for finger in (2,3,4,5):
            first = rig.pose.bones[f'finger{finger}-1.{side}']
            direction = (first.tail-first.head).normalized()
            desired = (direction*.25+desired_forward*.75).normalized()
            rotate_world(first, direction.rotation_difference(desired))
            for segment, angle in ((1,3),(2,9),(3,7)):
                rotate_world(rig.pose.bones[f'finger{finger}-{segment}.{side}'],
                             Quaternion(desired_across, math.radians(-angle*sign)))
        thumb = rig.pose.bones['finger1-1.'+side]
        direction = (thumb.tail-thumb.head).normalized()
        desired = (direction*.75+desired_forward*.25).normalized()
        rotate_world(thumb, direction.rotation_difference(desired))
    floor_z = -.004
    points = evaluated_points(body)
    matrix = rig.pose.bones['root'].matrix.copy()
    matrix.translation.z += floor_z+.0005-min(v.z for v in points)
    rig.pose.bones['root'].matrix = matrix
    update()
    points = evaluated_points(body)
    gaps = {side: min(p.z for p in points if sign*p.x > .035 and p.z < .20)-floor_z
            for side, sign in (('L',1),('R',-1))}
    if not all(-.0002 <= gap <= .003 for gap in gaps.values()):
        raise ValueError(f'Canonical support outside tolerance: {gaps}')
    return {'floor_z_m': floor_z, 'foot_support_gaps_m': gaps,
            'pose_rule': 'Reset all bases; symmetric legs, 18-degree upper arms / 12-degree forearms, relaxed front-facing hands and forward feet; ground translation only'}


def main():
    assert bpy.app.background
    parser = argparse.ArgumentParser()
    parser.add_argument('--blend', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    source, out = args.blend.resolve(), args.out.resolve()
    if out.exists() or out.with_suffix('.json').exists():
        raise ValueError('Refusing to overwrite canonical model or evidence')
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    body, rig = bpy.data.objects['GreenBody'], bpy.data.objects['GB_ReviewArmature']
    original = [(tuple(v.co), tuple((g.group,g.weight) for g in v.groups)) for v in body.data.vertices]
    report = {'errors': [], 'warnings': [], 'pose': canonical_pose(body, rig)}
    assert original == [(tuple(v.co), tuple((g.group,g.weight) for g in v.groups)) for v in body.data.vertices]
    check_original_mesh(body, report)
    check_armature_weights(body, report)
    assert not report['errors'], report['errors']
    bpy.context.scene['canonical_turnaround_pose'] = 'approved-turnaround-v1'
    bpy.context.scene['canonical_pose_source_sha256'] = source_hash
    bpy.context.scene['canonical_pose_preparer_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    bpy.context.scene['approved_for_animation'] = False
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert hashlib.sha256(source.read_bytes()).hexdigest() == source_hash
    report.update({'source': str(source), 'source_sha256': source_hash, 'source_unchanged': True,
                   'mesh_and_weights_unchanged': True, 'candidate': str(out),
                   'candidate_sha256': hashlib.sha256(out.read_bytes()).hexdigest()})
    out.with_suffix('.json').write_text(json.dumps(report, indent=2))
    print('CANONICAL_TURNAROUND', out, flush=True)


if __name__ == '__main__':
    main()
