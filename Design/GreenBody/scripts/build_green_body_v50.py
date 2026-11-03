"""Bounded torso-waist X cross-section study from V49.

The fixed front/back profiles retain a small waist-width deficit while the
side depth profile is already close.  This uses a central-body rest-space cage
field, excluding arms and legs, so it cannot be a camera-facing silhouette
hack and retains the underlying rig.
"""
import argparse, hashlib, json, sys
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from validate_green_body import check_armature_weights, check_original_mesh

def digest(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def smooth(a,b,x):
    t=max(0.,min(1.,(x-a)/(b-a))); return t*t*(3-2*t)

def main():
    assert bpy.app.background
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,default=ROOT/'GreenBody-v49-work.blend');p.add_argument('--out',type=Path,required=True);p.add_argument('--width',type=float,default=.035)
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);assert 0<a.width<=.08
    source,out=a.source.resolve(),a.out.resolve();assert not out.exists() and not out.with_suffix('.json').exists();before=digest(source)
    bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False);body=bpy.data.objects['GreenBody'];mesh=body.data
    original=[v.co.copy() for v in mesh.vertices];shapes={k.name:[p.co.copy() for p in k.data] for k in mesh.shape_keys.key_blocks};weights=[tuple((g.group,g.weight) for g in v.groups) for v in mesh.vertices]
    delta=[]
    for co in original:
        # Width is concentrated at the waist/low abdomen.  Central x and y
        # gates exclude arm/leg skin and preserve the pelvis/lat junctions.
        zband=smooth(.91,1.01,co.z)*(1-smooth(1.25,1.35,co.z))
        radial=smooth(.03,.12,abs(co.x))*(1-smooth(.25,.33,abs(co.x)))
        depth=1-smooth(.20,.34,abs(co.y+.07))
        delta.append(Vector((co.x*a.width*zband*radial*depth,0,0)))
    for v,d in zip(mesh.vertices,delta):v.co+=d
    for key in mesh.shape_keys.key_blocks:
        for i,p in enumerate(key.data):p.co=shapes[key.name][i]+delta[i]
    mesh.update();bpy.context.view_layer.update();basis=mesh.shape_keys.key_blocks['Basis'];err=max(((p.co-basis.data[i].co)-(shapes[key.name][i]-shapes['Basis'][i])).length for key in mesh.shape_keys.key_blocks for i,p in enumerate(key.data));assert err<1e-6
    assert weights==[tuple((g.group,g.weight) for g in v.groups) for v in mesh.vertices];assert all(c.driver.is_valid for c in mesh.shape_keys.animation_data.drivers)
    report={'errors':[],'warnings':[],'source':str(source),'source_sha256':before,'torso_waist_x_expansion_fraction':a.width,'changed_vertices':sum(d.length>1e-8 for d in delta),'maximum_displacement_m':max(d.length for d in delta),'relative_key_error_m':err,'weights_unchanged':True,'scope':'Central torso X-only rest-surface expansion copied to all relative keys; limbs, rig, pose, cameras, material and scoring unchanged.'}
    check_original_mesh(body,report);check_armature_weights(body,report);assert not report['errors'],report['errors'];assert report['original_mesh']['connected_component_count']==1 and report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire']==0
    bpy.context.scene['version']='V50 torso waist X cross-section study';bpy.context.scene['approved_for_animation']=False;bpy.context.scene.cycles.device='CPU';out.parent.mkdir(parents=True,exist_ok=True);bpy.ops.wm.save_as_mainfile(filepath=str(out));assert digest(source)==before
    report.update(candidate=str(out),candidate_sha256=digest(out),source_unchanged=True,builder_sha256=digest(__file__));out.with_suffix('.json').write_text(json.dumps(report,indent=2));print('V50_CANDIDATE',out,flush=True)
if __name__=='__main__':main()
