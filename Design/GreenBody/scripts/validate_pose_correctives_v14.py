"""Fresh-load driver and sampled-motion QA; read-only .blend sources."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import bpy
import numpy as np
from mathutils import Matrix,Vector

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from build_green_body_v14 import expected
from prepare_turnaround_pose_v2 import canonical_pose
from review_poses import reset,update,aim_chain
from review_poses_v2 import deep_squat,low_push_up,evaluated_points


def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main():
    p=argparse.ArgumentParser();p.add_argument('--blend',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--expected-refined-vertex-count',type=int,
                   help='Explicit topology-change audit: require this exact control-point count; V13 pointwise comparison is not applicable.')
    args=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    source=args.blend.resolve();before=digest(source)
    if args.out.exists():raise ValueError('Refusing overwrite')
    bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False)
    body,rig=bpy.data.objects['GreenBody'],bpy.data.objects['GB_ReviewArmature']
    control_vertex_count=len(body.data.vertices)
    if args.expected_refined_vertex_count is not None:
        assert control_vertex_count==args.expected_refined_vertex_count
    animation=body.data.shape_keys.animation_data
    assert len(animation.drivers)==2
    transfer_errors={}
    for curve in animation.drivers:
        assert curve.driver.is_simple_expression
        transfer_inputs=[i/1000 for i in range(1001)]+[.9999,.9999157444471376,.99999]
        transfer_errors[curve.data_path]=max(abs(curve.evaluate(x)-x) for x in transfer_inputs)
        assert transfer_errors[curve.data_path]<1e-6, ('Nonidentity driver transfer',transfer_errors)
        for var in curve.driver.variables:
            assert var.type=='LOC_DIFF'
            assert all(t.id==rig and t.bone_target for t in var.targets)
    keys={s:body.data.shape_keys.key_blocks['GB_Trapezius_PoseFill_'+s] for s in ('L','R')}
    def record():
        update()
        values={s:float(k.value) for s,k in keys.items()}
        for side,actual in values.items():
            want,distances=expected(rig,side)
            assert abs(actual-want)<2e-5, (side,actual,want,distances)
            assert .19999<=actual<=1.00001
        assert all(c.driver.is_valid for c in animation.drivers)
        return values
    canonical_pose(body,rig)
    neutral=record()
    original_matrices={b.name:b.matrix_basis.copy() for b in rig.pose.bones}
    sampled={}
    for name,fn in [('squat',deep_squat),('push-up',low_push_up)]:
        reset(rig);fn(rig)
        target={b.name:b.matrix_basis.copy() for b in rig.pose.bones}
        rows=[]
        for index in range(41):
            t=index/40
            for b in rig.pose.bones:
                a,ar,asc=original_matrices[b.name].decompose()
                z,zr,zsc=target[b.name].decompose()
                b.matrix_basis=Matrix.LocRotScale(a.lerp(z,t),ar.slerp(zr,t),asc.lerp(zsc,t))
            rows.append({'t':t,'weights':record()})
        sampled[name]=rows
    canonical_pose(body,rig)
    aim_chain(rig,'upperarm01.L','lowerarm01.L',(.018,-1,-.008))
    one_arm=record()
    assert one_arm['L']<.3 and one_arm['R']>.9999
    # Weight invariance to global location/orientation/scale is essential:
    # it must not be a correction tied to a particular view or global pose.
    saved=rig.matrix_world.copy()
    rig.matrix_world=Matrix.Translation(Vector((2,-3,1)))@Matrix.Rotation(1.3,4,'Y')@Matrix.Scale(1.7,4)@saved
    transformed=record()
    assert max(abs(one_arm[s]-transformed[s]) for s in keys)<2e-5
    rig.matrix_world=saved;update()
    camera_weights={}
    for obj in bpy.data.objects:
        if obj.type=='CAMERA':
            bpy.context.scene.camera=obj
            camera_weights[obj.name]=record()
            assert max(abs(one_arm[s]-camera_weights[obj.name][s]) for s in keys)<2e-5
    canonical_pose(body,rig)
    points=np.array([tuple(v) for v in evaluated_points(body)])
    filled=ROOT/'renders/v13-experiments/neck-foot/candidate.blend'
    filled_hash=digest(filled)
    bpy.ops.wm.open_mainfile(filepath=str(filled),use_scripts=False)
    filled_body,filled_rig=bpy.data.objects['GreenBody'],bpy.data.objects['GB_ReviewArmature']
    canonical_pose(filled_body,filled_rig)
    comparison=np.array([tuple(v) for v in evaluated_points(filled_body)])
    assert np.isfinite(points).all() and np.isfinite(comparison).all()
    if args.expected_refined_vertex_count is None:
        assert comparison.shape==points.shape
        distance=np.linalg.norm(points-comparison,axis=1)
        assert np.isfinite(distance).all()
        geometry_comparison={'status':'pointwise_comparison',
            'maximum_distance_m':float(distance.max()),
            'rms_distance_m':float(np.sqrt(np.mean(distance**2))),'vertex_count':len(distance),
            'comparison_source_sha256':filled_hash}
    else:
        assert comparison.shape!=points.shape, 'Use default pointwise mode for matching topology'
        geometry_comparison={'status':'not_comparable_different_topology',
            'candidate_control_vertex_count':control_vertex_count,
            'candidate_evaluated_vertex_count':len(points),
            'v13_evaluated_vertex_count':len(comparison),
            'comparison_source_sha256':filled_hash,
            'reason':'No vertex correspondence to V13; no distance or equivalence claim. Driver checks remain unchanged.'}
    assert digest(source)==before and digest(filled)==filled_hash
    result={'schema':'greenbody-pose-corrective-validation-v1','source':str(source),
        'source_sha256':before,'source_unchanged':True,'fresh_load_use_scripts':False,
        'all_drivers_valid_simple_expressions':True,'neutral_weights':neutral,
        'driver_transfer_max_errors':transfer_errors,
        'sampled_transitions':sampled,'left_arm_only':one_arm,'global_transform_weights':transformed,
        'camera_invariance':camera_weights,
        'neutral_vs_v13_evaluated_geometry':geometry_comparison,
        'limitations':['82 sampled transition states, not exhaustive motion validation.',
            'No automatic self-intersection check; actual pose renders must be visually inspected.',
            'Blender drivers are not automatically portable to iOS runtime.']}
    with args.out.open('x') as f:json.dump(result,f,indent=2)
    print(json.dumps({k:v for k,v in result.items() if k not in ('sampled_transitions','camera_invariance','limitations')},indent=2))


if __name__=='__main__':main()
