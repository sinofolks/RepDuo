"""Explicit pose-protocol revision, not a geometry edit or silent score change.

Same reference-led fixed rules for EVERY model; recapture old baselines.
Old prepare_turnaround_pose.py and all old evidence stay untouched.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix,Quaternion,Vector

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from review_poses import reset,aim_chain,set_world_rotation,rotate_world,update
from review_poses_v2 import evaluated_points
from validate_green_body import check_original_mesh,check_armature_weights

RULE = {'version':'approved-turnaround-pose-v2',
        'upper_leg_direction_abs_x_y_z':[.08,-.075,-1],
        'lower_leg_direction_abs_x_y_z':[.19,.10,-1],
        'upper_arm_lateral_degrees':13,'upper_arm_y':-.025,
        'forearm_lateral_degrees':18,'forearm_y':-.23,
        'foot_outward_yaw_degrees':20,'hand_inward_roll_degrees':30,
        'finger_curl_degrees':[6,16,10]}


def canonical_pose(body,rig):
    reset(rig)
    for side,sign in [('L',1),('R',-1)]:
        aim_chain(rig,'upperleg01.'+side,'lowerleg01.'+side,(sign*.08,-.075,-1))
        aim_chain(rig,'lowerleg01.'+side,'foot.'+side,(sign*.19,.10,-1))
        foot=rig.pose.bones['foot.'+side]
        ball=sum((rig.data.bones[f'toe{n}-1.{side}'].head_local for n in (2,3,4)),Vector())/3
        forward=ball-foot.bone.head_local
        yaw=-math.atan2(forward.x,-forward.y)+sign*math.radians(20)
        set_world_rotation(foot,Quaternion((0,0,1),yaw)@foot.bone.matrix_local.to_quaternion())
        aim_chain(rig,'upperarm01.'+side,'lowerarm01.'+side,
                  (sign*math.sin(math.radians(13)),-.025,-math.cos(math.radians(13))))
        aim_chain(rig,'lowerarm01.'+side,'wrist.'+side,
                  (sign*math.sin(math.radians(18)),-.23,-math.cos(math.radians(18))))
        wrist=rig.pose.bones['wrist.'+side]
        forward=(rig.pose.bones['finger3-1.'+side].head-wrist.head).normalized()
        across=rig.pose.bones['finger2-1.'+side].head-rig.pose.bones['finger5-1.'+side].head
        across=(across-forward*across.dot(forward)).normalized()
        current=Matrix((across,forward,across.cross(forward))).transposed()
        desired_forward=Vector((sign*.06,-.08,-1)).normalized()
        desired_across=Vector((-sign*math.cos(math.radians(30)),math.sin(math.radians(30)),0))
        desired_across=(desired_across-desired_forward*desired_across.dot(desired_forward)).normalized()
        target=Matrix((desired_across,desired_forward,desired_across.cross(desired_forward))).transposed()
        rotate_world(wrist,target@current.transposed())
        for finger in (2,3,4,5):
            first=rig.pose.bones[f'finger{finger}-1.{side}']
            direction=(first.tail-first.head).normalized()
            desired=(direction*.25+desired_forward*.75).normalized()
            rotate_world(first,direction.rotation_difference(desired))
            for segment,angle in enumerate(RULE['finger_curl_degrees'],1):
                rotate_world(rig.pose.bones[f'finger{finger}-{segment}.{side}'],Quaternion(desired_across,math.radians(-angle*sign)))
        thumb=rig.pose.bones['finger1-1.'+side]
        direction=(thumb.tail-thumb.head).normalized()
        desired=(direction*.75+desired_forward*.25).normalized()
        rotate_world(thumb,direction.rotation_difference(desired))
    floor_z=-.004
    points=evaluated_points(body)
    matrix=rig.pose.bones['root'].matrix.copy()
    matrix.translation.z+=floor_z+.0005-min(p.z for p in points)
    rig.pose.bones['root'].matrix=matrix
    update()
    points=evaluated_points(body)
    gaps={side:min(p.z for p in points if sign*p.x>.035 and p.z<.20)-floor_z
          for side,sign in [('L',1),('R',-1)]}
    assert all(-.0002<=g<=.003 for g in gaps.values()),gaps
    return {'floor_z_m':floor_z,'foot_support_gaps_m':gaps,'pose_rule':RULE}


def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    assert bpy.app.background
    p=argparse.ArgumentParser(); p.add_argument('--blend',type=Path,required=True); p.add_argument('--out',type=Path,required=True)
    args=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    source,out=args.blend.resolve(),args.out.resolve()
    if out.exists() or out.with_suffix('.json').exists(): raise ValueError('Refusing overwrite')
    source_hash=digest(source)
    bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False)
    body,rig=bpy.data.objects['GreenBody'],bpy.data.objects['GB_ReviewArmature']
    original=[(tuple(v.co),tuple((g.group,g.weight) for g in v.groups)) for v in body.data.vertices]
    report={'errors':[],'warnings':[],'pose':canonical_pose(body,rig)}
    assert original==[(tuple(v.co),tuple((g.group,g.weight) for g in v.groups)) for v in body.data.vertices]
    check_original_mesh(body,report); check_armature_weights(body,report)
    assert not report['errors'],report['errors']
    scene=bpy.context.scene
    scene['canonical_turnaround_pose']=RULE['version']
    scene['canonical_pose_source_sha256']=source_hash
    scene['canonical_pose_preparer_sha256']=digest(Path(__file__))
    scene['approved_for_animation']=False
    out.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert digest(source)==source_hash
    report.update({'source':str(source),'source_sha256':source_hash,'source_unchanged':True,
                   'mesh_and_weights_unchanged':True,'candidate':str(out),'candidate_sha256':digest(out)})
    out.with_suffix('.json').write_text(json.dumps(report,indent=2))
    print('CANONICAL_TURNAROUND_V2',out,flush=True)


if __name__=='__main__': main()
