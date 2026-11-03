"""Reference-led foot proportions on the real mesh and its toe rig.

No images, cameras, score rules, material or pose-protocol edits. One shared
closed mesh is rendered in all three views; all source versions are preserved.
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
    parser=argparse.ArgumentParser()
    parser.add_argument('--source',type=Path,default=ROOT/'GreenBody-v10-work.blend')
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--length',type=float,default=.25)
    parser.add_argument('--width',type=float,default=.18)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    assert 0<=args.length<=.4 and 0<=args.width<=.3
    source,out=args.source.resolve(),args.out.resolve()
    if out.exists() or out.with_suffix('.json').exists():raise ValueError('Refusing overwrite')
    before=digest(source)
    bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False)
    body,rig=bpy.data.objects['GreenBody'],bpy.data.objects['GB_ReviewArmature']
    old=[v.co.copy() for v in body.data.vertices]
    weights=[tuple((g.group,g.weight) for g in v.groups) for v in body.data.vertices]
    anchors={s:rig.data.bones['foot.'+s].head_local.copy() for s in ('L','R')}
    def transform(co):
        x,y,z=co
        if z>=.19 or abs(x)<.055:return co.copy()
        a=anchors['L' if x>0 else 'R']
        fade=1-smoothstep(.095,.19,z)
        forward=max(0,a.y-y)
        # Smooth ramp leaves heel and ankle anchor length unchanged.
        length_fade=smoothstep(.005,.045,forward)
        forefoot=smoothstep(.015,.09,forward)
        return Vector((x+(x-a.x)*args.width*fade*(.65+.35*forefoot),
                       y-forward*args.length*fade*length_fade,z))
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
        'parameters':{'forefoot_length_gain':args.length,'foot_width_gain':args.width},
        'vertices_changed':sum(v.co!=old[v.index] for v in body.data.vertices),
        'maximum_rest_displacement_m':max((v.co-old[v.index]).length for v in body.data.vertices),
        'rest_z_unchanged':all(v.co.z==old[v.index].z for v in body.data.vertices),
        'above_19cm_unchanged':all(v.co==old[v.index] for v in body.data.vertices if old[v.index].z>=.19),
        'weights_unchanged':weights==[tuple((g.group,g.weight) for g in v.groups) for v in body.data.vertices]}
    assert all(report[k] for k in ('rest_z_unchanged','above_19cm_unchanged','weights_unchanged'))
    assert report['maximum_rest_displacement_m']<.10
    check_original_mesh(body,report);check_armature_weights(body,report)
    assert not report['errors'],report['errors']
    assert report['original_mesh']['connected_component_count']==1
    assert report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire']==0
    report['support']=canonical_pose(body,rig)
    bpy.context.scene['version']='V11 reference-v3 foot proportions study'
    bpy.context.scene['approved_for_animation']=False
    bpy.context.scene.cycles.device='CPU'
    out.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert digest(source)==before
    report.update({'source':str(source),'source_sha256':before,'source_unchanged':True,
                   'builder_sha256':digest(__file__),'candidate':str(out),'candidate_sha256':digest(out)})
    out.with_suffix('.json').write_text(json.dumps(report,indent=2))
    print('V11_CANDIDATE',out,flush=True)


if __name__=='__main__':main()
