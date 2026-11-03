"""Small face-profile study; all geometry changes stay on the existing head mesh."""
import argparse,hashlib,json,math,sys
from pathlib import Path
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from validate_green_body import check_original_mesh,check_armature_weights
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def g(x,c,w):return math.exp(-.5*((x-c)/w)**2)
def smooth(a,b,x):
 t=max(0.,min(1.,(x-a)/(b-a)));return t*t*(3-2*t)
def main():
 assert bpy.app.background
 p=argparse.ArgumentParser();p.add_argument('--source',type=Path,default=ROOT/'GreenBody-v28-work.blend');p.add_argument('--out',type=Path,required=True);p.add_argument('--nose',type=float,default=.007);p.add_argument('--chin',type=float,default=.006)
 a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);assert 0<=a.nose<=.012 and 0<=a.chin<=.012
 source,out=a.source.resolve(),a.out.resolve();assert not out.exists() and not out.with_suffix('.json').exists();before=digest(source)
 bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False);body=bpy.data.objects['GreenBody'];mesh=body.data
 original=[v.co.copy() for v in mesh.vertices];shapes={k.name:[p.co.copy() for p in k.data] for k in mesh.shape_keys.key_blocks};weights=[tuple((g.group,g.weight) for g in v.groups) for v in mesh.vertices]
 delta=[]
 for co in original:
  x,y,z=co; local_x=x-.015;front=smooth(.030,.088,-y); head=smooth(1.59,1.62,z)*(1-smooth(1.74,1.77,z))
  nose=a.nose*g(local_x,0,.012)*g(z,1.681,.013)*front*head
  bridge=.35*a.nose*g(local_x,0,.014)*g(z,1.700,.022)*front*head
  chin=a.chin*g(local_x,0,.033)*g(z,1.625,.016)*front*head
  # A shallow philtrum gap prevents nose and chin reads merging into a beak.
  recess=.20*a.chin*g(local_x,0,.024)*g(z,1.651,.009)*front*head
  delta.append(Vector((0,-nose-bridge-chin+recess,0)))
 for v,d in zip(mesh.vertices,delta):v.co+=d
 for k in mesh.shape_keys.key_blocks:
  for i,p in enumerate(k.data):p.co=shapes[k.name][i]+delta[i]
 mesh.update();bpy.context.view_layer.update();basis=mesh.shape_keys.key_blocks['Basis'];err=max(((p.co-basis.data[i].co)-(shapes[k.name][i]-shapes['Basis'][i])).length for k in mesh.shape_keys.key_blocks for i,p in enumerate(k.data));assert err<1e-6
 assert weights==[tuple((g.group,g.weight) for g in v.groups) for v in mesh.vertices];assert all(c.driver.is_valid for c in mesh.shape_keys.animation_data.drivers)
 report={'errors':[],'warnings':[],'source':str(source),'source_sha256':before,'nose_m':a.nose,'chin_m':a.chin,'changed_vertices':sum(d.length>1e-8 for d in delta),'maximum_displacement_m':max(d.length for d in delta),'relative_key_error_m':err,'weights_unchanged':True,'scope':'Local anterior facial profile only; rig, pose, cameras, reference, material and scoring unchanged.'}
 check_original_mesh(body,report);check_armature_weights(body,report);assert not report['errors'],report['errors'];assert report['original_mesh']['connected_component_count']==1 and report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire']==0
 bpy.context.scene['version']='V32 bounded face-profile study';bpy.context.scene['approved_for_animation']=False;bpy.context.scene.cycles.device='CPU';out.parent.mkdir(parents=True,exist_ok=True);bpy.ops.wm.save_as_mainfile(filepath=str(out));assert digest(source)==before
 report.update(candidate=str(out),candidate_sha256=digest(out),source_unchanged=True,builder_sha256=digest(__file__));out.with_suffix('.json').write_text(json.dumps(report,indent=2));print('V32_CANDIDATE',out,flush=True)
if __name__=='__main__':main()
