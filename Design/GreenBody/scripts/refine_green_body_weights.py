"""Local geodesic weight diffusion study, preserving rest geometry and rig.

Diagnostic candidates only: normalization and lower weight variation do not
prove better deformation. Inspect actual posed renders before promotion.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from build_green_body import smoothstep
from validate_green_body import check_original_mesh,check_armature_weights


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def diffuse(body,rig,region,amount,iterations):
    bone_groups=[g for g in body.vertex_groups if g.name in rig.data.bones and rig.data.bones[g.name].use_deform]
    columns={g.index:i for i,g in enumerate(bone_groups)}
    values=np.zeros((len(body.data.vertices),len(bone_groups)))
    for v in body.data.vertices:
        for g in v.groups:
            if g.group in columns: values[v.index,columns[g.group]]=g.weight
    original=values.copy()
    if region=='hands':
        centers=[(rig.data.bones[f'finger{f}-{part}.{side}'].head_local,.012,.028)
                 for side in ('L','R') for f in range(1,6) for part in (2,3)]
    else:
        centers=[(rig.data.bones['lowerleg01.'+side].head_local,.055,.12) for side in ('L','R')]
    mask=np.array([max(1-smoothstep(inner,outer,(v.co-center).length) for center,inner,outer in centers)
                   for v in body.data.vertices])
    edges=np.array([list(e.vertices) for e in body.data.edges],dtype=int)
    coordinates=np.array([list(v.co) for v in body.data.vertices])
    edge_weight=1/np.maximum(np.linalg.norm(coordinates[edges[:,0]]-coordinates[edges[:,1]],axis=1),1e-5)
    source=np.r_[edges[:,0],edges[:,1]]; target=np.r_[edges[:,1],edges[:,0]]
    coeff=np.r_[edge_weight,edge_weight]
    degree=np.bincount(source,weights=coeff,minlength=len(values))
    def variation(x):
        active=(mask[edges[:,0]]+mask[edges[:,1]])*.5
        return float(np.sum(np.sum((x[edges[:,0]]-x[edges[:,1]])**2,axis=1)*active*edge_weight))
    before=variation(values)
    for _ in range(iterations):
        average=np.zeros_like(values)
        np.add.at(average,source,values[target]*coeff[:,None])
        average/=np.maximum(degree[:,None],1e-12)
        values+=(average-values)*(amount*mask[:,None])
        values=np.maximum(values,0)
        values/=np.maximum(values.sum(axis=1,keepdims=True),1e-12)
    selected=np.flatnonzero(mask>0)
    for group in bone_groups:
        group.remove(selected.tolist())
    for index in selected:
        weights=values[index]
        # Threshold only numerical dust; keep all real bone influences.
        weights[weights<1e-8]=0; weights/=weights.sum()
        for column in np.flatnonzero(weights):
            bone_groups[column].add([int(index)],float(weights[column]),'REPLACE')
    assert np.array_equal(original[mask==0],values[mask==0]) or np.max(np.abs(original[mask==0]-values[mask==0]))<1e-7
    return {'region':region,'amount':amount,'iterations':iterations,'affected_vertices':len(selected),
            'local_edge_weight_variation_before':before,'local_edge_weight_variation_after':variation(values),
            'metric_scope':'Binding smoothness only; not a likeness/deformation quality score',
            'maximum_influences':int((values>1e-8).sum(axis=1).max())}


def main():
    assert bpy.app.background
    p=argparse.ArgumentParser(); p.add_argument('--source',type=Path,required=True); p.add_argument('--out',type=Path,required=True)
    p.add_argument('--region',choices=('hands','knees'),required=True)
    p.add_argument('--amount',type=float,default=.45); p.add_argument('--iterations',type=int,default=8)
    args=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    if not 0<args.amount<=.7 or not 1<=args.iterations<=20: raise ValueError('Invalid diffusion parameters')
    source,out=args.source.resolve(),args.out.resolve()
    if out.exists() or out.with_suffix('.json').exists(): raise ValueError('Refusing overwrite')
    source_hash=digest(source)
    bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False)
    body,rig=bpy.data.objects['GreenBody'],bpy.data.objects['GB_ReviewArmature']
    coordinates=[tuple(v.co) for v in body.data.vertices]
    pose={b.name:[list(row) for row in b.matrix_basis] for b in rig.pose.bones}
    report={'errors':[],'warnings':[],'study':diffuse(body,rig,args.region,args.amount,args.iterations)}
    assert coordinates==[tuple(v.co) for v in body.data.vertices]
    assert pose=={b.name:[list(row) for row in b.matrix_basis] for b in rig.pose.bones}
    report['rest_geometry_and_pose_unchanged']=True
    check_original_mesh(body,report); check_armature_weights(body,report)
    assert not report['errors'],report['errors']
    scene=bpy.context.scene; scene.cycles.device='CPU'
    scene['version']='V10 local binding study: '+args.region
    scene['approved_for_animation']=False
    scene['weight_study']=json.dumps(report['study'])
    out.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert digest(source)==source_hash
    report.update({'source':str(source),'source_sha256':source_hash,'source_unchanged':True,
                   'builder_sha256':digest(Path(__file__)),'candidate':str(out),'candidate_sha256':digest(out)})
    out.with_suffix('.json').write_text(json.dumps(report,indent=2))
    print('WEIGHT_STUDY',out,flush=True)


if __name__=='__main__': main()
