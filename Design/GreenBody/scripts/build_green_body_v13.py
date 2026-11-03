"""Local posterior neck/trapezius volume, one real mesh in all projections."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import bpy

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from build_green_body import smoothstep
from validate_green_body import check_original_mesh,check_armature_weights


def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main():
    assert bpy.app.background
    p=argparse.ArgumentParser()
    p.add_argument('--source',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--strength',type=float,default=1)
    args=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    assert 0<=args.strength<=1
    source,out=args.source.resolve(),args.out.resolve()
    if out.exists() or out.with_suffix('.json').exists():raise ValueError('Refusing overwrite')
    before=digest(source)
    bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False)
    body,rig=bpy.data.objects['GreenBody'],bpy.data.objects['GB_ReviewArmature']
    old=[v.co.copy() for v in body.data.vertices]
    weights=[tuple((g.group,g.weight) for g in v.groups) for v in body.data.vertices]
    for v in body.data.vertices:
        x,y,z=v.co
        if not 1.32<z<1.66:continue
        lateral=1-smoothstep(.13,.25,abs(x-.015*smoothstep(1.48,1.66,z)))
        posterior=smoothstep(-.035,.045,y)
        fade=smoothstep(1.32,1.36,z)*(1-smoothstep(1.62,1.66,z))
        v.co.y+=args.strength*.040*math.exp(-.5*((z-1.507)/.065)**2)*lateral*posterior*fade
    body.data.update()
    report={'errors':[],'warnings':[],
        'parameters':{'strength':args.strength,'peak_displacement_m':.040,'center_z_m':1.507,'sigma_m':.065},
        'vertices_changed':sum(v.co!=old[v.index] for v in body.data.vertices),
        'maximum_rest_displacement_m':max((v.co-old[v.index]).length for v in body.data.vertices),
        'rest_xz_unchanged':all(v.co.x==old[v.index].x and v.co.z==old[v.index].z for v in body.data.vertices),
        'outside_neck_region_unchanged':all(v.co==old[v.index] for v in body.data.vertices if not 1.32<old[v.index].z<1.66),
        'weights_unchanged':weights==[tuple((g.group,g.weight) for g in v.groups) for v in body.data.vertices]}
    assert all(report[k] for k in ('rest_xz_unchanged','outside_neck_region_unchanged','weights_unchanged'))
    check_original_mesh(body,report);check_armature_weights(body,report)
    assert not report['errors'],report['errors']
    assert report['original_mesh']['connected_component_count']==1
    assert report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire']==0
    bpy.context.scene['version']='V13 reference-v3 posterior neck volume study'
    bpy.context.scene['approved_for_animation']=False
    bpy.context.scene.cycles.device='CPU'
    out.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert digest(source)==before
    report.update({'source':str(source),'source_sha256':before,'source_unchanged':True,
                   'builder_sha256':digest(__file__),'candidate':str(out),'candidate_sha256':digest(out)})
    out.with_suffix('.json').write_text(json.dumps(report,indent=2))
    print('V13_CANDIDATE',out,flush=True)


if __name__=='__main__':main()
