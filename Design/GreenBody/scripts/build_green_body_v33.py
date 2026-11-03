"""Measured lower-body transverse contour study from V32."""
import argparse,hashlib,json,sys
from pathlib import Path
import bpy
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from validate_green_body import check_original_mesh,check_armature_weights
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def smooth(a,b,x):
 t=max(0.,min(1.,(x-a)/(b-a)));return t*t*(3-2*t)
def band(z,a,b,c,d):return smooth(a,b,z)*(1-smooth(c,d,z))
def main():
 assert bpy.app.background
 p=argparse.ArgumentParser();p.add_argument('--source',type=Path,default=ROOT/'GreenBody-v32-work.blend');p.add_argument('--out',type=Path,required=True);p.add_argument('--hip-scale',type=float,default=.96);p.add_argument('--shin-scale',type=float,default=.95)
 a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);assert .90<=a.hip_scale<=1 and .90<=a.shin_scale<=1
 source,out=a.source.resolve(),a.out.resolve();assert not out.exists() and not out.with_suffix('.json').exists();before=digest(source)
 bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False);body=bpy.data.objects['GreenBody'];mesh=body.data
 original=[v.co.copy() for v in mesh.vertices];shapes={k.name:[p.co.copy() for p in k.data] for k in mesh.shape_keys.key_blocks};weights=[tuple((g.group,g.weight) for g in v.groups) for v in mesh.vertices]
 delta=[]
 for co in original:
  hip=band(co.z,.77,.83,.98,1.05);shin=band(co.z,.19,.28,.58,.66)
  factor=1+(a.hip_scale-1)*hip+(a.shin_scale-1)*shin
  delta.append((co.x-.015)*(factor-1))
 for v,d in zip(mesh.vertices,delta):v.co.x+=d
 for k in mesh.shape_keys.key_blocks:
  for i,p in enumerate(k.data):p.co.x=shapes[k.name][i].x+delta[i]
 mesh.update();bpy.context.view_layer.update();basis=mesh.shape_keys.key_blocks['Basis'];err=max(abs((p.co.x-basis.data[i].co.x)-(shapes[k.name][i].x-shapes['Basis'][i].x)) for k in mesh.shape_keys.key_blocks for i,p in enumerate(k.data));assert err<1e-6
 assert weights==[tuple((g.group,g.weight) for g in v.groups) for v in mesh.vertices];assert all(c.driver.is_valid for c in mesh.shape_keys.animation_data.drivers)
 report={'errors':[],'warnings':[],'source':str(source),'source_sha256':before,'hip_scale':a.hip_scale,'shin_scale':a.shin_scale,'changed_vertices':sum(abs(d)>1e-8 for d in delta),'maximum_displacement_m':max(abs(d) for d in delta),'relative_key_error_m':err,'weights_unchanged':True,'scope':'Hip and shin rest X contours only; no rig, pose, reference, camera, material or scoring change.'}
 check_original_mesh(body,report);check_armature_weights(body,report);assert not report['errors'],report['errors'];assert report['original_mesh']['connected_component_count']==1 and report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire']==0
 bpy.context.scene['version']='V33 lower-body transverse contour study';bpy.context.scene['approved_for_animation']=False;bpy.context.scene.cycles.device='CPU';out.parent.mkdir(parents=True,exist_ok=True);bpy.ops.wm.save_as_mainfile(filepath=str(out));assert digest(source)==before
 report.update(candidate=str(out),candidate_sha256=digest(out),source_unchanged=True,builder_sha256=digest(__file__));out.with_suffix('.json').write_text(json.dumps(report,indent=2));print('V33_CANDIDATE',out,flush=True)
if __name__=='__main__':main()
