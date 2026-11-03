"""Smooth real mesh/rig proportion changes based on approved landmark evidence.

The original concept required higher knees than the new approved turnaround.
This study lowers knees and torso landmarks, without editing cameras or pose rules.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from prepare_turnaround_pose import canonical_pose
from build_green_body import smoothstep
from validate_green_body import check_original_mesh, check_armature_weights

# Shared-tangent cubic displacement profile; C1 continuity, no ring steps.
KNOTS = [(0,0),(.13,0),(.30,-.015),(.59,-.035),(.83,-.025),
         (1.02,-.020),(1.40,-.020),(1.54,0),(1.83,0)]


def sample_profile(z, knots):
    if z <= knots[0][0] or z >= knots[-1][0]: return 0
    i = next(i for i in range(len(knots)-1) if knots[i][0] <= z <= knots[i+1][0])
    def tangent(k):
        if k in (0,len(knots)-1): return 0
        a,b,c = knots[k-1:k+2]
        d0,d1 = (b[1]-a[1])/(b[0]-a[0]),(c[1]-b[1])/(c[0]-b[0])
        if d0*d1 <= 0: return 0
        h0,h1 = b[0]-a[0],c[0]-b[0]
        return 3*(h0+h1)/((2*h1+h0)/d0+(h1+2*h0)/d1)
    (z0,a),(z1,b) = knots[i:i+2]
    h=z1-z0; t=(z-z0)/h
    return (2*t**3-3*t*t+1)*a+(t**3-2*t*t+t)*h*tangent(i)+(-2*t**3+3*t*t)*b+(t**3-t*t)*h*tangent(i+1)


def offset(z): return sample_profile(z,KNOTS)


WIDTH_KNOTS = [(.65,0),(.85,.08),(.98,.14),(1.08,.12),(1.20,.07),
               (1.34,.06),(1.44,.07),(1.53,0)]
KNEE_ONLY_KNOTS = [(0,0),(.13,0),(.30,-.012),(.59,-.035),(.78,-.010),(.95,0),(1.83,0)]
RESTRAINED_WIDTH_KNOTS = [(.65,0),(.85,.035),(.98,.07),(1.08,.06),(1.20,.045),
                          (1.34,.055),(1.44,.06),(1.53,0)]


def lateral_volume(body,rig,strength,knots=WIDTH_KNOTS,leg_extra=.10):
    for v in body.data.vertices:
        x,y,z=v.co
        trunk=sample_profile(z,knots)*(1-smoothstep(.20,.30,abs(x)))
        v.co.x += x*trunk*strength
    for side,sign in [('L',1),('R',-1)]:
        for start_name,end_name in [('upperleg01.','lowerleg01.'),('lowerleg01.','foot.')]:
            start=rig.data.bones[start_name+side].head_local
            end=rig.data.bones[end_name+side].head_local
            axis=end-start
            for v in body.data.vertices:
                if sign*v.co.x <= .035: continue
                d=v.co-start
                t=d.dot(axis)/axis.length_squared
                radial=d-axis*t
                if .06<t<.94 and radial.length<.15:
                    fade=smoothstep(.06,.24,t)*(1-smoothstep(.72,.94,t))
                    v.co.x += radial.x*leg_extra*fade*strength


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    assert bpy.app.background
    parser=argparse.ArgumentParser()
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--source',type=Path,default=ROOT/'GreenBody-v7-work.blend')
    parser.add_argument('--strength',type=float,default=1)
    parser.add_argument('--width-strength',type=float,default=0)
    parser.add_argument('--height-mode',choices=('full','knee-only'),default='full')
    parser.add_argument('--width-mode',choices=('full','restrained'),default='full')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    if not all(0 <= s <= 1 for s in (args.strength,args.width_strength)): raise ValueError('Invalid strength')
    source,out=args.source.resolve(),args.out.resolve()
    if out.exists() or out.with_suffix('.json').exists(): raise ValueError('Refusing overwrite')
    source_hash=digest(source)
    height_knots=KNEE_ONLY_KNOTS if args.height_mode=='knee-only' else KNOTS
    width_knots=RESTRAINED_WIDTH_KNOTS if args.width_mode=='restrained' else WIDTH_KNOTS
    leg_extra=0 if args.width_mode=='restrained' else .10
    samples=[i/10000 for i in range(18301)]
    warped=[z+args.strength*sample_profile(z,height_knots) for z in samples]
    min_derivative=min((b-a)*10000 for a,b in zip(warped,warped[1:]))
    assert min_derivative > .6
    bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False)
    body,rig=bpy.data.objects['GreenBody'],bpy.data.objects['GB_ReviewArmature']
    original=[v.co.copy() for v in body.data.vertices]
    weights=[tuple((g.group,g.weight) for g in v.groups) for v in body.data.vertices]
    def transform(v): return Vector((v.x,v.y,v.z+args.strength*sample_profile(v.z,height_knots)))
    for v in body.data.vertices: v.co=transform(v.co)
    bones={b.name:(b.head_local.copy(),b.tail_local.copy()) for b in rig.data.bones}
    bpy.context.view_layer.objects.active=rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for bone in rig.data.edit_bones:
        a,b=bones[bone.name]
        bone.head, bone.tail=transform(a),transform(b)
    bpy.ops.object.mode_set(mode='OBJECT')
    lateral_volume(body,rig,args.width_strength,width_knots,leg_extra)
    body.data.update()
    report={'errors':[],'warnings':[], 'parameters':{'strength':args.strength,'knots':height_knots,
            'width_strength':args.width_strength,'width_knots':width_knots,'leg_extra':leg_extra,
            'height_mode':args.height_mode,'width_mode':args.width_mode},
            'minimum_vertical_map_derivative':min_derivative,'support':canonical_pose(body,rig),
            'maximum_rest_displacement_m':max((v.co-original[v.index]).length for v in body.data.vertices),
            'head_and_sole_unchanged':all(v.co == original[v.index] for v in body.data.vertices if original[v.index].z >= 1.54 or original[v.index].z <= .13),
            'weights_unchanged':weights == [tuple((g.group,g.weight) for g in v.groups) for v in body.data.vertices]}
    assert report['head_and_sole_unchanged'] and report['weights_unchanged']
    check_original_mesh(body,report); check_armature_weights(body,report)
    assert not report['errors'],report['errors']
    assert report['original_mesh']['connected_component_count']==1
    assert report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire']==0
    scene=bpy.context.scene
    scene['version']='V9 approved-turnaround anatomical height study'
    scene['v9_builder_sha256']=digest(Path(__file__))
    scene['v9_parameters']=json.dumps(report['parameters'])
    scene['approved_for_animation']=False
    scene.cycles.device='CPU'
    out.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert digest(source)==source_hash
    report.update({'source':str(source),'source_sha256':source_hash,'source_unchanged':True,
                   'builder_sha256':digest(Path(__file__)),'candidate':str(out),'candidate_sha256':digest(out)})
    out.with_suffix('.json').write_text(json.dumps(report,indent=2))
    print('V9_CANDIDATE',out,flush=True)


if __name__=='__main__': main()
