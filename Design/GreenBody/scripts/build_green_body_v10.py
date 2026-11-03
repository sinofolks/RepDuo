"""Bounded sagittal muscle-volume sculpt, identical real mesh in all views."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from build_green_body import smoothstep
from validate_green_body import check_original_mesh,check_armature_weights


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def sculpt(body,rig,strength):
    edits={'thigh':set(),'calf':set()}
    for side,sign in [('L',1),('R',-1)]:
        for label,start_name,end_name,radius,shift,fill in [
            ('thigh','upperleg01.','lowerleg01.',.15,.008,.020),
            ('calf','lowerleg01.','foot.',.10,.012,.012)]:
            start=rig.data.bones[start_name+side].head_local
            end=rig.data.bones[end_name+side].head_local
            axis=end-start
            for v in body.data.vertices:
                if sign*v.co.x <= .035: continue
                delta=v.co-start
                t=delta.dot(axis)/axis.length_squared
                radial=delta-axis*t
                if not .04<t<.96 or radial.length>=radius: continue
                fade=smoothstep(.04,.22,t)*(1-smoothstep(.74,.96,t))
                fade*=1-smoothstep(radius*.85,radius,radial.length)
                posterior=smoothstep(-.035,.045,radial.y)
                v.co.y += strength*fade*(shift+fill*posterior)
                edits[label].add(v.index)
    return {k:len(v) for k,v in edits.items()}


def main():
    assert bpy.app.background
    p=argparse.ArgumentParser()
    p.add_argument('--source',type=Path,default=ROOT/'GreenBody-v9-work.blend')
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--strength',type=float,default=1)
    args=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    if not 0<=args.strength<=1.5: raise ValueError('Invalid strength')
    source,out=args.source.resolve(),args.out.resolve()
    if out.exists() or out.with_suffix('.json').exists(): raise ValueError('Refusing overwrite')
    source_hash=digest(source)
    bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False)
    body,rig=bpy.data.objects['GreenBody'],bpy.data.objects['GB_ReviewArmature']
    original=[v.co.copy() for v in body.data.vertices]
    weights=[tuple((g.group,g.weight) for g in v.groups) for v in body.data.vertices]
    pose={b.name:[list(row) for row in b.matrix_basis] for b in rig.pose.bones}
    changed=sculpt(body,rig,args.strength)
    body.data.update()
    report={'errors':[],'warnings':[],'parameters':{'strength':args.strength},'changed_vertices':changed,
            'maximum_rest_displacement_m':max((v.co-original[v.index]).length for v in body.data.vertices),
            'rest_xz_unchanged':all(v.co.x==original[v.index].x and v.co.z==original[v.index].z for v in body.data.vertices),
            'head_and_upper_body_unchanged':all(v.co==original[v.index] for v in body.data.vertices if original[v.index].z>=1.05),
            'weights_unchanged':weights==[tuple((g.group,g.weight) for g in v.groups) for v in body.data.vertices],
            'pose_unchanged':pose=={b.name:[list(row) for row in b.matrix_basis] for b in rig.pose.bones}}
    assert all(report[k] for k in ('rest_xz_unchanged','head_and_upper_body_unchanged','weights_unchanged','pose_unchanged'))
    assert report['maximum_rest_displacement_m'] <= .045
    check_original_mesh(body,report); check_armature_weights(body,report)
    assert not report['errors'],report['errors']
    assert report['original_mesh']['connected_component_count']==1
    assert report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire']==0
    scene=bpy.context.scene
    scene['version']='V10 reference-led sagittal leg sculpt'
    scene['v10_builder_sha256']=digest(Path(__file__))
    scene['v10_parameters']=json.dumps(report['parameters'])
    scene['approved_for_animation']=False
    scene.cycles.device='CPU'
    out.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert digest(source)==source_hash
    report.update({'source':str(source),'source_sha256':source_hash,'source_unchanged':True,
                   'builder_sha256':digest(Path(__file__)),'candidate':str(out),'candidate_sha256':digest(out)})
    out.with_suffix('.json').write_text(json.dumps(report,indent=2))
    print('V10_CANDIDATE',out,flush=True)


if __name__=='__main__': main()
