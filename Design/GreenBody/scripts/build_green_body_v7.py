"""Bounded 3D volume study against the USER-APPROVED three-view design.

Changes torso depth/width, limb radial volume, and anatomical foot dimensions.
All candidates use the same locked turnaround pose/cameras, never pixel warps.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
from build_green_body import smoothstep
from prepare_turnaround_pose import canonical_pose
from validate_green_body import check_original_mesh, check_armature_weights


def body_volume(body, rig, strength):
    for vertex in body.data.vertices:
        x,y,z = vertex.co
        w = smoothstep(.90,1.02,z)*(1-smoothstep(1.45,1.52,z))
        w *= 1-smoothstep(.12,.205,abs(x))
        vertex.co.x *= 1+.05*w*strength
        vertex.co.y += (y+.015)*.18*w*strength
    for side, sign in (('L',1),('R',-1)):
        for first, last, extra, radius in [('upperleg01.','lowerleg01.',.10,.145),
                                           ('lowerleg01.','foot.',.11,.085)]:
            start = rig.data.bones[first+side].head_local
            end = rig.data.bones[last+side].head_local
            axis = end-start
            for vertex in body.data.vertices:
                if sign*vertex.co.x <= .035:
                    continue
                d = vertex.co-start
                t = d.dot(axis)/axis.length_squared
                radial = d-axis*t
                if .04 < t < .97 and radial.length < radius:
                    w = smoothstep(.04,.23,t)*(1-smoothstep(.73,.97,t))
                    w *= 1-smoothstep(radius*.83,radius,radial.length)
                    vertex.co += radial*extra*strength*w


def foot_volume(body, rig, strength):
    frames = {}
    for side, sign in (('L',1),('R',-1)):
        ankle = rig.data.bones['foot.'+side].head_local.copy()
        ball = sum((rig.data.bones[f'toe{n}-1.{side}'].head_local for n in (2,3,4)), Vector())/3
        forward = ball-ankle
        forward.z = 0
        forward.normalize()
        frames[side] = (sign, ankle, forward, Vector((-forward.y,forward.x,0)))
    def transform(point, side):
        sign, ankle, forward, across = frames[side]
        if sign*point.x <= .035 or point.z >= .20:
            return point.copy()
        offset = point-ankle
        longitudinal, transverse = offset.dot(forward), offset.dot(across)
        fade = smoothstep(.015,.075,longitudinal)*(1-smoothstep(.12,.20,point.z))
        return point + strength*fade*(forward*max(0,longitudinal)*.22+across*transverse*.35)
    for vertex in body.data.vertices:
        side = 'L' if vertex.co.x > 0 else 'R'
        vertex.co = transform(vertex.co, side)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for bone in rig.data.edit_bones:
        if bone.name.startswith(('foot.','toe')) and bone.name.endswith(('.L','.R')):
            side = bone.name[-1]
            bone.head = transform(bone.head, side)
            bone.tail = transform(bone.tail, side)
    bpy.ops.object.mode_set(mode='OBJECT')


def main():
    assert bpy.app.background
    parser = argparse.ArgumentParser()
    parser.add_argument('--source',type=Path,default=ROOT/'GreenBody-v6-work.blend')
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--body-strength',type=float,default=1)
    parser.add_argument('--foot-strength',type=float,default=1)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    if not all(0 <= value <= 1.5 for value in (args.body_strength,args.foot_strength)):
        raise ValueError('Strength outside bounded [0,1.5] study')
    source,out = args.source.resolve(),args.out.resolve()
    if out.exists() or out.with_suffix('.json').exists():
        raise ValueError('Refusing to overwrite model or evidence')
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False)
    body,rig = bpy.data.objects['GreenBody'],bpy.data.objects['GB_ReviewArmature']
    original = [v.co.copy() for v in body.data.vertices]
    weights = [tuple((g.group,g.weight) for g in v.groups) for v in body.data.vertices]
    body_volume(body,rig,args.body_strength)
    foot_volume(body,rig,args.foot_strength)
    body.data.update()
    report = {'parameters':{'body_strength':args.body_strength,'foot_strength':args.foot_strength},
              'errors':[],'warnings':[],'support':canonical_pose(body,rig)}
    assert weights == [tuple((g.group,g.weight) for g in v.groups) for v in body.data.vertices]
    assert all(v.co == original[v.index] for v in body.data.vertices if original[v.index].z >= 1.52)
    report['original_weights_unchanged'] = True
    report['head_unchanged'] = True
    report['max_rest_displacement_m'] = max((v.co-original[v.index]).length for v in body.data.vertices)
    check_original_mesh(body,report)
    check_armature_weights(body,report)
    assert not report['errors'],report['errors']
    assert report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire'] == 0
    assert report['original_mesh']['connected_component_count'] == 1
    scene = bpy.context.scene
    scene['version'] = 'V7 approved-turnaround volume study'
    scene['v7_parameters'] = json.dumps(report['parameters'],sort_keys=True)
    scene['v7_builder_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    scene['approved_for_animation'] = False
    scene.cycles.device = 'CPU'
    out.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert hashlib.sha256(source.read_bytes()).hexdigest() == source_hash
    report.update({'source':str(source),'source_sha256':source_hash,'source_unchanged':True,
                   'candidate':str(out),'candidate_sha256':hashlib.sha256(out.read_bytes()).hexdigest()})
    out.with_suffix('.json').write_text(json.dumps(report,indent=2))
    print('V7_CANDIDATE',out,flush=True)


if __name__ == '__main__': main()
