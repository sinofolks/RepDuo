"""Bounded medial-upper-arm sculpt; preserve all pose-corrective shape deltas.

The neutral capture has an overly closed axilla/upper-arm gap. Thin only the
medial upper-arm surface; retain shoulder's outer contour, rig and weights.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from build_green_body import smoothstep
from validate_green_body import check_original_mesh,check_armature_weights


def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main():
    assert bpy.app.background
    p=argparse.ArgumentParser()
    p.add_argument('--source',type=Path,default=ROOT/'GreenBody-v14-work.blend')
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--amount',type=float,default=.016)
    p.add_argument('--mode',choices=('medial','translate','translate-smooth'),default='medial')
    args=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    assert 0<=args.amount<=.025
    source,out=args.source.resolve(),args.out.resolve()
    if out.exists() or out.with_suffix('.json').exists():raise ValueError('Refusing overwrite')
    source_hash=digest(source)
    bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False)
    body,rig=bpy.data.objects['GreenBody'],bpy.data.objects['GB_ReviewArmature']
    original=[v.co.copy() for v in body.data.vertices]
    weights=[tuple((g.group,g.weight) for g in v.groups) for v in body.data.vertices]
    shapes={k.name:[p.co.copy() for p in k.data] for k in body.data.shape_keys.key_blocks}
    delta=[Vector() for _ in original]
    side_counts={}
    for side,sign in [('L',1),('R',-1)]:
        start=rig.data.bones['upperarm01.'+side].head_local
        end=rig.data.bones['lowerarm01.'+side].head_local
        axis=end-start;unit=axis.normalized()
        medial=Vector((-sign,0,0));medial=(medial-unit*medial.dot(unit)).normalized()
        groups={g.index for g in body.vertex_groups if g.name.startswith('upperarm') and g.name.endswith('.'+side)}
        count=0
        for i,co in enumerate(original):
            vec=co-start;t=vec.dot(axis)/axis.length_squared
            radial=vec-axis*t
            arm_weight=sum(w for g,w in weights[i] if g in groups)
            if not .04<t<.85 or radial.length>.14 or arm_weight<.1:continue
            inner=radial.dot(medial)
            amount=args.amount*smoothstep(.04,.18,t)*(1-smoothstep(.52,.85,t))
            if args.mode=='translate-smooth':amount=args.amount*math.sin(math.pi*(t-.04)/.81)**2
            if args.mode=='medial':amount*=smoothstep(.005,.045,inner)
            amount*=smoothstep(.1,.65,arm_weight)
            amount*=1-smoothstep(.115,.14,radial.length)
            if amount:
                delta[i]-=medial*amount;count+=1
        side_counts[side]=count
    for i,v in enumerate(body.data.vertices):v.co=original[i]+delta[i]
    for key in body.data.shape_keys.key_blocks:
        for i,point in enumerate(key.data):point.co=shapes[key.name][i]+delta[i]
    body.data.update();bpy.context.view_layer.update()
    max_shape_error=0.
    basis=body.data.shape_keys.key_blocks['Basis']
    for key in body.data.shape_keys.key_blocks:
        for i,point in enumerate(key.data):
            old_delta=shapes[key.name][i]-shapes['Basis'][i]
            max_shape_error=max(max_shape_error,((point.co-basis.data[i].co)-old_delta).length)
    assert max_shape_error<1e-6
    assert weights==[tuple((g.group,g.weight) for g in v.groups) for v in body.data.vertices]
    report={'errors':[],'warnings':[], 'amount_m':args.amount,'mode':args.mode,'changed_vertices':side_counts,
        'max_rest_displacement_m':max(v.length for v in delta),
        'shape_relative_delta_max_error_m':max_shape_error,'skin_weights_unchanged':True,
        'rig_unchanged':True,'shape_key_names':list(shapes),
        'all_drivers_valid':all(c.driver.is_valid for c in body.data.shape_keys.animation_data.drivers)}
    assert report['all_drivers_valid']
    check_original_mesh(body,report);check_armature_weights(body,report)
    assert not report['errors'],report['errors']
    assert report['original_mesh']['connected_component_count']==1
    assert report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire']==0
    bpy.context.scene['version']='V15 '+args.mode+' upper-arm volume study; V14 corrective keys preserved'
    bpy.context.scene['approved_for_animation']=False
    bpy.context.scene.cycles.device='CPU'
    out.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert digest(source)==source_hash
    report.update({'source':str(source),'source_sha256':source_hash,'source_unchanged':True,
        'candidate':str(out),'candidate_sha256':digest(out),'builder_sha256':digest(__file__)})
    out.with_suffix('.json').write_text(json.dumps(report,indent=2))
    print('V15_CANDIDATE',out,flush=True)


if __name__=='__main__':main()
