"""V4 proportion studies on the real mesh and skeleton, never on pixels.

Read V3.1, adjust anatomical proportions in rest space, preserve skin weights,
then re-establish standing support. Old assets and scoring remain immutable.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from build_green_body import smoothstep
from body_geometry_v2 import _rotate
from stance_v3 import plant_feet
from validate_green_body import check_original_mesh, check_armature_weights

DEFAULTS = {"ankle_lift": .035, "knee_lift": .045, "leg_twist": 0,
            "calf_extra": 0, "forefoot_extra": 0,"upperarm_extra":0,
            "torso_yaw":0,"nasal_projection":0,"thumb_relax":0,
            "foot_yaw_R":-38,"foot_yaw_L":46,"toe_rounding":0,"restrained_instep":0}


def lift(z, p):
    # Raising ankle/knee centers while retaining the sole, pelvis and height
    # is a genuine proportion edit: taller instep and shorter femoral segment.
    lower = p["ankle_lift"] + (p["knee_lift"]-p["ankle_lift"])*smoothstep(.13,.52,z)
    return lower*smoothstep(.004,.068,z)*(1-smoothstep(.57,1.00,z))


def proportion(body, rig, p):
    if not (0 <= p["ankle_lift"] <= .060 and 0 <= p["knee_lift"] <= .070):
        raise ValueError("Outside bounded ankle/knee proportion range")
    bases = {bone.name:bone.matrix_basis.copy() for bone in rig.pose.bones}
    bones = {bone.name:(bone.head_local.copy(),bone.tail_local.copy()) for bone in rig.data.bones}
    vertices = [v.co.copy() for v in body.data.vertices]
    for v in body.data.vertices:
        foot_fade=1-p['restrained_instep']*(1-smoothstep(.04,.13,v.co.z))
        v.co.z += lift(v.co.z,p)*foot_fade
    bpy.context.view_layer.objects.active=rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for bone in rig.data.edit_bones:
        head,tail=bones[bone.name]
        bone.head=Vector((head.x,head.y,head.z+lift(head.z,p)))
        bone.tail=Vector((tail.x,tail.y,tail.z+lift(tail.z,p)))
    bpy.ops.object.mode_set(mode="OBJECT")
    for bone in rig.pose.bones:
        bone.matrix_basis=bases[bone.name]
    bpy.context.view_layer.update()
    # Calf fullness is radial to the actual updated tibial axis, not a
    # screen-space translation of the silhouette.
    for side,sign in (("L",1),("R",-1)):
        knee=rig.data.bones["lowerleg01."+side].head_local
        ankle=rig.data.bones["foot."+side].head_local
        axis=ankle-knee
        for v in body.data.vertices:
            if sign*v.co.x < .045 or not .13 < v.co.z < .63:
                continue
            d=v.co-knee
            t=d.dot(axis)/axis.length_squared
            radial=d-axis*t
            if .05 < t < .90 and radial.length < .08:
                fade=smoothstep(.05,.22,t)*(1-smoothstep(.64,.90,t))
                v.co += radial*p["calf_extra"]*fade
    body.data.update()
    maximum=max((v.co-original).length for v,original in zip(body.data.vertices,vertices))
    return {"proportion_stage_max_rest_displacement_m":maximum,"body_height_unchanged":True,
            "method":"Monotonic skeletal/body height map, optional foot-surface attenuation, and local radial calf sculpt",
            "foot_surface_attenuation":p['restrained_instep']}


def twist_legs(rig, degrees):
    for side in ("L","R"):
        upper=rig.pose.bones["upperleg01."+side]
        lower=rig.pose.bones["lowerleg01."+side]
        foot=rig.pose.bones["foot."+side]
        target_ankle=foot.head.copy()
        orientation=foot.matrix.to_quaternion()
        # Twist around the long axis while retaining the existing knee point.
        axis=(lower.head-upper.head).normalized()
        _rotate(upper,Quaternion(axis,math.radians(-degrees)))
        direction=foot.head-lower.head
        desired=target_ankle-lower.head
        _rotate(lower,direction.normalized().rotation_difference(desired.normalized()))
        matrix=orientation.to_matrix().to_4x4()
        matrix.translation=foot.head.copy()
        foot.matrix=matrix
        bpy.context.view_layer.update()


def orient_feet(rig,p):
    # Rest-proportion edits change the foot's local frame. Reusing its old
    # local quaternion would introduce unintended pitch/roll. Reconstruct
    # the same explicit world yaw against the NEW rest frame instead.
    settings=json.loads(bpy.context.scene.get('v3_parameters','{}')).get('stance',{})
    for side in ('L','R'):
        foot=rig.pose.bones['foot.'+side]
        yaw=p.get('foot_yaw_'+side,settings.get('foot_yaw_'+side,46 if side=='L' else -38))
        orientation=Quaternion((0,0,1),math.radians(yaw))@foot.bone.matrix_local.to_quaternion()
        matrix=orientation.to_matrix().to_4x4()
        matrix.translation=foot.head.copy()
        foot.matrix=matrix
        bpy.context.view_layer.update()


def upper_refinement(body,rig,p):
    for side in ('L','R'):
        start=rig.data.bones['upperarm01.'+side].head_local
        end=rig.data.bones['lowerarm01.'+side].head_local
        axis=end-start
        for vertex in body.data.vertices:
            offset=vertex.co-start
            t=offset.dot(axis)/axis.length_squared
            radial=offset-axis*t
            if .05<t<.97 and radial.length<.085:
                influence=smoothstep(.05,.25,t)*(1-smoothstep(.75,.97,t))
                influence*=1-smoothstep(.06,.085,radial.length)
                vertex.co+=radial*p['upperarm_extra']*influence
    for vertex in body.data.vertices:
        x,y,z=vertex.co
        if 1.64<z<1.74 and y<-.07:
            influence=math.exp(-.5*(x/.014)**2-.5*((z-1.685)/.021)**2)
            vertex.co.y-=p['nasal_projection']*influence
    body.data.update()
    _rotate(rig.pose.bones['spine05'],Quaternion((0,0,1),math.radians(p['torso_yaw'])))
    for side in ('L','R'):
        thumb=rig.pose.bones['finger1-1.'+side]
        wrist=rig.pose.bones['wrist.'+side]
        forward=(rig.pose.bones['finger3-1.'+side].head-wrist.head).normalized()
        direction=(thumb.tail-thumb.head).normalized()
        desired=(direction*(1-p['thumb_relax'])+forward*p['thumb_relax']).normalized()
        _rotate(thumb,direction.rotation_difference(desired))


def foot_refinement(body,rig,p):
    for side,sign in (('L',1),('R',-1)):
        ankle=rig.data.bones['foot.'+side].head_local
        ball=sum((rig.data.bones[f'toe{toe}-1.{side}'].head_local for toe in (2,3,4)),Vector())/3
        forward=ball-ankle
        forward.z=0
        forward.normalize()
        across=Vector((-forward.y,forward.x,0))
        for v in body.data.vertices:
            if sign*v.co.x<.04 or v.co.z>.19:
                continue
            offset=v.co-ankle
            longitudinal=offset.dot(forward)
            transverse=offset.dot(across)
            fade=smoothstep(.025,.090,longitudinal)
            v.co+=across*transverse*p['forefoot_extra']*fade
        # Round existing individual toe cross-sections; preserve all joints,
        # original topology and skin groups rather than adding disconnected pads.
        for toe in range(1,6):
            bone=rig.data.bones.get(f'toe{toe}-1.{side}')
            if not bone:continue
            start=bone.head_local
            end=bone.tail_local
            axis=end-start
            groups={g.index for g in body.vertex_groups if g.name.startswith(f'toe{toe}-') and g.name.endswith('.'+side)}
            for v in body.data.vertices:
                weight=sum(g.weight for g in v.groups if g.group in groups)
                if weight<.05:continue
                offset=v.co-start
                t=offset.dot(axis)/axis.length_squared
                radial=offset-axis*t
                v.co+=radial*p['toe_rounding']*min(1,weight)*smoothstep(0,.5,t)
    body.data.update()


def main():
    assert bpy.app.background,"Use a separate background process"
    parser=argparse.ArgumentParser()
    parser.add_argument("--out",type=Path,required=True)
    parser.add_argument("--params-json",default="{}")
    parser.add_argument("--source",type=Path,default=ROOT/"GreenBody-v3.1.blend")
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    out=args.out.resolve()
    if out.exists() or out.with_suffix('.json').exists():
        raise ValueError("Refusing to overwrite existing candidate or evidence")
    source=args.source.resolve()
    digest=hashlib.sha256(source.read_bytes()).hexdigest()
    p={**DEFAULTS,**json.loads(args.params_json)}
    for name,value in p.items():
        if not isinstance(value,(int,float)) or not math.isfinite(value):
            raise ValueError(f'Invalid numeric parameter: {name}')
    for name,low,high in [('leg_twist',-40,40),('calf_extra',0,.3),
                          ('upperarm_extra',0,.3),('forefoot_extra',0,.3),
                          ('toe_rounding',0,.4),('thumb_relax',0,.6),
                          ('restrained_instep',0,1),('nasal_projection',0,.012),
                          ('torso_yaw',-15,15)]:
        if not low<=p[name]<=high:
            raise ValueError(f'Parameter outside bounded anatomical study: {name}')
    bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False)
    body=bpy.data.objects["GreenBody"]
    rig=bpy.data.objects["GB_ReviewArmature"]
    geometry=proportion(body,rig,p)
    upper_refinement(body,rig,p)
    foot_refinement(body,rig,p)
    orient_feet(rig,p)
    twist_legs(rig,p['leg_twist'])
    contact=plant_feet(body,rig)
    assert all(-.0002<=z-contact['floor_z_m']<=.002 for z in contact['minimum_z_m'].values()),contact
    report={"parameters":p,"geometry_edit":geometry,"support":contact,"errors":[],"warnings":[]}
    check_original_mesh(body,report)
    check_armature_weights(body,report)
    assert not report['errors'],report['errors']
    assert report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire']==0
    assert report['original_mesh']['connected_component_count']==1
    scene=bpy.context.scene
    scene['version']='Green Body V4 proportion study'
    scene['approved_for_animation']=False
    scene['v4_parameters']=json.dumps(p,sort_keys=True)
    scene['v4_builder_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    scene.cycles.device='CPU'
    out.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert hashlib.sha256(source.read_bytes()).hexdigest()==digest
    report.update({"source":str(source),"source_sha256":digest,"source_unchanged":True,
                   "candidate":str(out),"candidate_sha256":hashlib.sha256(out.read_bytes()).hexdigest()})
    out.with_suffix('.json').write_text(json.dumps(report,indent=2))
    print('V4_CANDIDATE',out,flush=True)


if __name__=='__main__':
    main()
