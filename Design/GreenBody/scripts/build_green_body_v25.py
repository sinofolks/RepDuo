"""Bounded limb-path and foot-stance geometry study on V24 topology.

The approved fixed turnaround pose is not touched.  This changes only rest
surface positions, identically in every relative corrective shape key.
"""
import argparse, hashlib, json, math, sys
from pathlib import Path
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from validate_green_body import check_original_mesh,check_armature_weights

def digest(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def smooth(a,b,x):
    t=max(0.,min(1.,(x-a)/(b-a))); return t*t*(3-2*t)
def gauss(x,c,w): return math.exp(-.5*((x-c)/w)**2)

def main():
    assert bpy.app.background
    p=argparse.ArgumentParser()
    p.add_argument('--source',type=Path,default=ROOT/'GreenBody-v24-work.blend')
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--arm-bow',type=float,default=.025)
    p.add_argument('--wrist-return',type=float,default=.014)
    p.add_argument('--foot-inset',type=float,default=.035)
    p.add_argument('--hand-inset',type=float,default=0.)
    p.add_argument('--shoulder-inset',type=float,default=0.)
    p.add_argument('--foot-width-scale',type=float,default=0.)
    p.add_argument('--elbow-bow',type=float,default=0.)
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    assert 0<=a.arm_bow<=.04 and 0<=a.wrist_return<=.03 and 0<=a.foot_inset<=.07 and 0<=a.hand_inset<=.05 and 0<=a.shoulder_inset<=.03 and 0<=a.foot_width_scale<=.30 and 0<=a.elbow_bow<=.03
    source,out=a.source.resolve(),a.out.resolve()
    assert not out.exists() and not out.with_suffix('.json').exists()
    before=digest(source)
    bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False)
    body=bpy.data.objects['GreenBody']; mesh=body.data
    original=[v.co.copy() for v in mesh.vertices]
    shapes={k.name:[p.co.copy() for p in k.data] for k in mesh.shape_keys.key_blocks}
    weights=[tuple((g.group,g.weight) for g in v.groups) for v in mesh.vertices]
    arm_groups={}
    for side in ('L','R'):
        names={n+'.'+side for n in ('upperarm01','upperarm02','lowerarm01','lowerarm02','wrist')}
        names|={g.name for g in body.vertex_groups if g.name.endswith('.'+side) and (g.name.startswith('finger') or g.name.startswith('metacarpal'))}
        arm_groups[side]={g.index for g in body.vertex_groups if g.name in names}
    foot_groups={}
    hand_groups={}
    root_arm_groups={}
    foot_anchors={}
    for side in ('L','R'):
        names={'foot.'+side}|{g.name for g in body.vertex_groups if g.name.endswith('.'+side) and g.name.startswith('toe')}
        foot_groups[side]={g.index for g in body.vertex_groups if g.name in names}
        foot_anchors[side]=next(b for b in bpy.data.objects['GB_ReviewArmature'].data.bones if b.name=='foot.'+side).head_local.x
        hand_groups[side]={g.index for g in body.vertex_groups if g.name.endswith('.'+side) and
                           (g.name.startswith('finger') or g.name.startswith('metacarpal') or g.name=='wrist.'+side)}
        root_arm_groups[side]={g.index for g in body.vertex_groups if g.name in {'shoulder01.'+side,'upperarm01.'+side,'upperarm02.'+side}}
    delta=[]
    for co,row in zip(original,weights):
        x,y,z=co; d=Vector()
        for side,sign in (('L',1),('R',-1)):
            arm=sum(w for g,w in row if g in arm_groups[side])
            foot=sum(w for g,w in row if g in foot_groups[side])
            hand=sum(w for g,w in row if g in hand_groups[side])
            root_arm=sum(w for g,w in row if g in root_arm_groups[side])
            # A smooth outward elbow reach, then a smaller inward wrist return,
            # matches the actual front-view residual without moving shoulder rest bones.
            arm_dx=sign*(a.arm_bow*gauss(z,1.075,.115)+a.elbow_bow*gauss(z,.995,.055)-a.wrist_return*gauss(z,.82,.085))*smooth(.12,.72,arm)
            # The front reference shows a narrower toe/forefoot stance. Only the
            # foot chain moves; ankle/leg geometry is left alone.
            foot_dx=-sign*a.foot_inset*smooth(.06,.26,-y)*smooth(.10,.72,foot)
            foot_dx+=(x-foot_anchors[side])*a.foot_width_scale*smooth(.10,.72,foot)
            hand_dx=-sign*a.hand_inset*smooth(.10,.70,hand)
            root_dx=-sign*a.shoulder_inset*gauss(z,1.315,.105)*smooth(.08,.65,root_arm)
            d.x+=arm_dx+foot_dx+hand_dx+root_dx
        delta.append(d)
    # Total end-effector displacement is capped independently from individual
    # knobs because hand and foot fields can overlap at transition vertices.
    assert max(d.length for d in delta)<=.075001
    for v,d in zip(mesh.vertices,delta):v.co+=d
    for key in mesh.shape_keys.key_blocks:
        for i,p in enumerate(key.data):p.co=shapes[key.name][i]+delta[i]
    mesh.update();bpy.context.view_layer.update()
    basis=mesh.shape_keys.key_blocks['Basis']
    err=max(((p.co-basis.data[i].co)-(shapes[k.name][i]-shapes['Basis'][i])).length for k in mesh.shape_keys.key_blocks for i,p in enumerate(k.data))
    assert err<1e-6
    assert weights==[tuple((g.group,g.weight) for g in v.groups) for v in mesh.vertices]
    assert all(c.driver.is_valid for c in mesh.shape_keys.animation_data.drivers)
    report={'errors':[],'warnings':[],'source':str(source),'source_sha256':before,
      'arm_bow_m':a.arm_bow,'wrist_return_m':a.wrist_return,'foot_inset_m':a.foot_inset,
      'hand_inset_m':a.hand_inset,
      'shoulder_inset_m':a.shoulder_inset,
      'foot_width_scale':a.foot_width_scale,
      'elbow_bow_m':a.elbow_bow,
      'changed_vertices':sum(d.length>1e-8 for d in delta),'maximum_displacement_m':max(d.length for d in delta),
      'relative_key_error_m':err,'weights_unchanged':True,
      'scope':'Rest-surface limb path and forefoot stance only; rig, fixed pose, camera, reference and material unchanged.'}
    check_original_mesh(body,report);check_armature_weights(body,report)
    assert not report['errors'],report['errors']
    assert report['original_mesh']['connected_component_count']==1
    assert report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire']==0
    bpy.context.scene['version']='V25 bounded limb path and foot stance study';bpy.context.scene['approved_for_animation']=False;bpy.context.scene.cycles.device='CPU'
    out.parent.mkdir(parents=True,exist_ok=True);bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert digest(source)==before
    report.update(candidate=str(out),candidate_sha256=digest(out),source_unchanged=True,builder_sha256=digest(__file__))
    out.with_suffix('.json').write_text(json.dumps(report,indent=2));print('V25_CANDIDATE',out,flush=True)
if __name__=='__main__':main()
