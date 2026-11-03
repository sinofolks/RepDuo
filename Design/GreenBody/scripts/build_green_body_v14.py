"""Convert V13's static neck fill to bilateral bone-driven corrective shapes.

Same geometry for all cameras. Keys respond continuously to arm elevation and
elbow flexion, retaining20% added fill at raised/flexed extremes. No pose names,
frame numbers, camera properties or reference pixels enter the driver.
"""
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
from prepare_turnaround_pose_v2 import canonical_pose
from review_poses import reset,update
from review_poses_v2 import deep_squat,low_push_up
from pose_corrective_math import DRIVER_EXPRESSION,weight_from_distances


def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def rig_state(rig):
    return {b.name:(tuple(b.head_local),tuple(b.tail_local),b.roll if hasattr(b,'roll') else tuple(b.matrix_local.to_quaternion())) for b in rig.data.bones}


def pairs(side):
    s,e,w='upperarm01.'+side,'lowerarm01.'+side,'wrist.'+side
    return {'a':(s,e),'b':(e,w),'c':(s,w),'d':(s,'spine05'),'e':(e,'spine05')}


def expected(rig,side):
    points={n:rig.matrix_world@b.head for n,b in rig.pose.bones.items()}
    distances={k:(points[a]-points[b]).length for k,(a,b) in pairs(side).items()}
    return weight_from_distances(**distances),distances


def main():
    assert bpy.app.background
    p=argparse.ArgumentParser()
    p.add_argument('--out',type=Path,required=True)
    args=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    out=args.out.resolve()
    if out.exists() or out.with_suffix('.json').exists():raise ValueError('Refusing overwrite')
    base=ROOT/'renders/v13-experiments/foot10-source/candidate.blend'
    filled=ROOT/'renders/v13-experiments/neck-foot/candidate.blend'
    hashes={str(p):digest(p) for p in (base,filled)}
    bpy.ops.wm.open_mainfile(filepath=str(filled),use_scripts=False)
    filled_body=bpy.data.objects['GreenBody']
    target=[v.co.copy() for v in filled_body.data.vertices]
    topology=[tuple(p.vertices) for p in filled_body.data.polygons]
    filled_weights=[tuple((g.group,g.weight) for g in v.groups) for v in filled_body.data.vertices]
    filled_rig=rig_state(bpy.data.objects['GB_ReviewArmature'])
    bpy.ops.wm.open_mainfile(filepath=str(base),use_scripts=False)
    body,rig=bpy.data.objects['GreenBody'],bpy.data.objects['GB_ReviewArmature']
    assert body.data.shape_keys is None
    assert topology==[tuple(p.vertices) for p in body.data.polygons]
    assert filled_weights==[tuple((g.group,g.weight) for g in v.groups) for v in body.data.vertices]
    assert filled_rig==rig_state(rig)
    basis=[v.co.copy() for v in body.data.vertices]
    delta=[a-b for a,b in zip(target,basis)]
    assert all(abs(d.x)<1e-7 and abs(d.z)<1e-7 and -.000001<=d.y<=.040001 for d in delta)
    body.shape_key_add(name='Basis',from_mix=False)
    keys={}
    for side in ('L','R'):
        key=body.shape_key_add(name='GB_Trapezius_PoseFill_'+side,from_mix=False)
        for i,(point,d) in enumerate(zip(basis,delta)):
            left=smoothstep(-.08,.11,point.x)
            partition=left if side=='L' else 1-left
            key.data[i].co=point+d*partition
        curve=key.driver_add('value')
        driver=curve.driver
        driver.type='SCRIPTED'
        for name,(a,b) in pairs(side).items():
            var=driver.variables.new();var.name=name;var.type='LOC_DIFF'
            for target,bone in zip(var.targets,(a,b)):
                target.id=rig;target.bone_target=bone;target.transform_space='WORLD_SPACE'
        driver.expression=DRIVER_EXPRESSION
        assert driver.expression==DRIVER_EXPRESSION
        assert driver.is_simple_expression
        keys[side]=key
    body.data.update();update()
    evidence={}
    for name in ('neutral','squat','push-up'):
        reset(rig)
        if name=='neutral':canonical_pose(body,rig)
        elif name=='squat':deep_squat(rig)
        else:low_push_up(rig)
        update()
        evidence[name]={}
        for side,key in keys.items():
            want,distances=expected(rig,side)
            got=float(key.value)
            assert abs(got-want)<2e-5,(name,side,got,want)
            evidence[name][side]={'actual_weight':got,'expected_weight':want,'distances_m':distances}
        if name=='neutral':assert all(v['actual_weight']>.9999 for v in evidence[name].values()),evidence[name]
        else:assert max(v['actual_weight'] for v in evidence[name].values())<.5,evidence[name]
    canonical_pose(body,rig);update()
    assert all(v.co==basis[v.index] for v in body.data.vertices)
    # Partition of unity: both keys at1 reconstruct the approved study sculpt.
    max_error=max(((keys['L'].data[i].co-basis[i])+(keys['R'].data[i].co-basis[i])-delta[i]).length for i in range(len(basis)))
    assert max_error<1e-6
    report={'errors':[],'warnings':[], 'basis_mesh_and_weights_unchanged':True,
        'sources':hashes,'driver_expression':DRIVER_EXPRESSION,'pose_checks':evidence,
        'neutral_reconstruction_max_error_m':max_error,
        'shape_names':[k.name for k in keys.values()],
        'limitations':['Artistic pose correction, not a biomechanical volume simulation.',
                      'Only decreases the added V13 neck fill; does not fix existing V12 knee/axilla defects.',
                      'Drivers require equivalent runtime logic when exported; iOS is not modified.']}
    check_original_mesh(body,report);check_armature_weights(body,report)
    assert not report['errors'],report['errors']
    bpy.context.scene['version']='V14 bilateral bone-driven trapezius corrective study'
    bpy.context.scene['approved_for_animation']=False
    bpy.context.scene.cycles.device='CPU'
    out.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert hashes=={str(p):digest(p) for p in (base,filled)}
    report.update({'candidate':str(out),'candidate_sha256':digest(out),'builder_sha256':digest(__file__),
                   'source_unchanged':True})
    out.with_suffix('.json').write_text(json.dumps(report,indent=2))
    print('V14_CANDIDATE',out,json.dumps(evidence),flush=True)


if __name__=='__main__':main()
