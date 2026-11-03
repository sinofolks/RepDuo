"""Arm hanging-path study using existing skin groups; no pose protocol mutation."""
import argparse,hashlib,json,sys
from pathlib import Path
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from validate_green_body import check_original_mesh,check_armature_weights
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def smooth(a,b,x):
 t=max(0.,min(1.,(x-a)/(b-a)));return t*t*(3-2*t)
def main():
 assert bpy.app.background
 p=argparse.ArgumentParser();p.add_argument('--source',type=Path,default=ROOT/'GreenBody-v36-work.blend');p.add_argument('--out',type=Path,required=True);p.add_argument('--hand-drop',type=float,default=.035)
 a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);assert 0<=a.hand_drop<=.05
 source,out=a.source.resolve(),a.out.resolve();assert not out.exists() and not out.with_suffix('.json').exists();before=digest(source)
 bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False);body=bpy.data.objects['GreenBody'];mesh=body.data
 original=[v.co.copy() for v in mesh.vertices];shapes={k.name:[p.co.copy() for p in k.data] for k in mesh.shape_keys.key_blocks};weights=[tuple((g.group,g.weight) for g in v.groups) for v in mesh.vertices]
 arm={}
 for side in ('L','R'):
  names={g.name for g in body.vertex_groups if g.name.endswith('.'+side) and (g.name.startswith(('upperarm','lowerarm','finger','metacarpal')) or g.name=='wrist.'+side)}
  arm[side]={g.index for g in body.vertex_groups if g.name in names}
 delta=[]
 for co,row in zip(original,weights):
  influence=max(sum(w for g,w in row if g in arm[s]) for s in arm)
  # z is rest height: shoulder remains fixed; elbow gains about half the hand
  # displacement and the hand reaches the specified maximum smoothly.
  path=1-smooth(.79,1.34,co.z)
  delta.append(Vector((0,0,-a.hand_drop*path*smooth(.10,.70,influence))))
 for v,d in zip(mesh.vertices,delta):v.co+=d
 for k in mesh.shape_keys.key_blocks:
  for i,p in enumerate(k.data):p.co=shapes[k.name][i]+delta[i]
 mesh.update();bpy.context.view_layer.update();basis=mesh.shape_keys.key_blocks['Basis'];err=max(((p.co-basis.data[i].co)-(shapes[k.name][i]-shapes['Basis'][i])).length for k in mesh.shape_keys.key_blocks for i,p in enumerate(k.data));assert err<1e-6
 assert weights==[tuple((g.group,g.weight) for g in v.groups) for v in mesh.vertices];assert all(c.driver.is_valid for c in mesh.shape_keys.animation_data.drivers)
 report={'errors':[],'warnings':[],'source':str(source),'source_sha256':before,'hand_drop_m':a.hand_drop,'changed_vertices':sum(d.length>1e-8 for d in delta),'maximum_displacement_m':max(d.length for d in delta),'relative_key_error_m':err,'weights_unchanged':True,'scope':'Arm-surface hanging path only; bones, fixed pose, cameras, reference, material and scoring unchanged.'}
 check_original_mesh(body,report);check_armature_weights(body,report);assert not report['errors'],report['errors'];assert report['original_mesh']['connected_component_count']==1 and report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire']==0
 bpy.context.scene['version']='V38 arm hanging-path study';bpy.context.scene['approved_for_animation']=False;bpy.context.scene.cycles.device='CPU';out.parent.mkdir(parents=True,exist_ok=True);bpy.ops.wm.save_as_mainfile(filepath=str(out));assert digest(source)==before
 report.update(candidate=str(out),candidate_sha256=digest(out),source_unchanged=True,builder_sha256=digest(__file__));out.with_suffix('.json').write_text(json.dumps(report,indent=2));print('V38_CANDIDATE',out,flush=True)
if __name__=='__main__':main()
