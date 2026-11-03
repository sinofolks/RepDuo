"""Small reference-led head/neck lateral alignment, actual mesh and rig.

The approved front (and its authorized mirrored back) has the head roughly
6 canonical pixels to screen right of the limb-bounds center. This is an
explicit small asymmetric head/neck adjustment, not a camera or image shift.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from build_green_body import smoothstep
from validate_green_body import check_original_mesh,check_armature_weights
from prepare_turnaround_pose_v2 import canonical_pose


def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main():
    assert bpy.app.background
    p=argparse.ArgumentParser()
    p.add_argument('--source',type=Path,default=ROOT/'GreenBody-v10-work.blend')
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--offset',type=float,default=.015)
    args=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    assert 0<=args.offset<=.02
    source,out=args.source.resolve(),args.out.resolve()
    if out.exists() or out.with_suffix('.json').exists():raise ValueError('Refusing overwrite')
    before=digest(source)
    bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False)
    body,rig=bpy.data.objects['GreenBody'],bpy.data.objects['GB_ReviewArmature']
    old=[v.co.copy() for v in body.data.vertices]
    weights=[tuple((g.group,g.weight) for g in v.groups) for v in body.data.vertices]
    def transform(co):
        x,y,z=co
        return Vector((x+args.offset*smoothstep(1.48,1.66,z),y,z))
    for v in body.data.vertices:v.co=transform(v.co)
    bones={b.name:(b.head_local.copy(),b.tail_local.copy()) for b in rig.data.bones}
    bpy.context.view_layer.objects.active=rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for bone in rig.data.edit_bones:
        a,b=bones[bone.name]
        bone.head,bone.tail=transform(a),transform(b)
    bpy.ops.object.mode_set(mode='OBJECT')
    body.data.update()
    report={'errors':[],'warnings':[],
        'parameters':{'head_lateral_offset_m':args.offset,'smooth_transition_z_m':[1.48,1.66]},
        'vertices_changed':sum(v.co!=old[v.index] for v in body.data.vertices),
        'maximum_rest_displacement_m':max((v.co-old[v.index]).length for v in body.data.vertices),
        'rest_yz_unchanged':all(v.co.y==old[v.index].y and v.co.z==old[v.index].z for v in body.data.vertices),
        'below_148cm_unchanged':all(v.co==old[v.index] for v in body.data.vertices if old[v.index].z<=1.48),
        'weights_unchanged':weights==[tuple((g.group,g.weight) for g in v.groups) for v in body.data.vertices]}
    assert all(report[k] for k in ('rest_yz_unchanged','below_148cm_unchanged','weights_unchanged'))
    check_original_mesh(body,report);check_armature_weights(body,report)
    assert not report['errors'],report['errors']
    assert report['original_mesh']['connected_component_count']==1
    assert report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire']==0
    report['support']=canonical_pose(body,rig)
    bpy.context.scene['version']='V12 reference-v3 asymmetric head-neck alignment study'
    bpy.context.scene['approved_for_animation']=False
    bpy.context.scene.cycles.device='CPU'
    out.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert digest(source)==before
    report.update({'source':str(source),'source_sha256':before,'source_unchanged':True,
                   'builder_sha256':digest(__file__),'candidate':str(out),'candidate_sha256':digest(out)})
    out.with_suffix('.json').write_text(json.dumps(report,indent=2))
    print('V12_CANDIDATE',out,flush=True)


if __name__=='__main__':main()
