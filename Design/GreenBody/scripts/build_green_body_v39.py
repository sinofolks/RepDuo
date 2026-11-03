"""Rig-consistent arm-length study from V36; no pose/camera/reference changes."""
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
 p=argparse.ArgumentParser();p.add_argument('--source',type=Path,default=ROOT/'GreenBody-v36-work.blend');p.add_argument('--out',type=Path,required=True);p.add_argument('--length',type=float,default=.025)
 a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);assert 0<=a.length<=.05
 source,out=a.source.resolve(),a.out.resolve();assert not out.exists() and not out.with_suffix('.json').exists();before=digest(source)
 bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False);body=bpy.data.objects['GreenBody'];rig=bpy.data.objects['GB_ReviewArmature'];mesh=body.data
 original=[v.co.copy() for v in mesh.vertices];shapes={k.name:[p.co.copy() for p in k.data] for k in mesh.shape_keys.key_blocks};weights=[tuple((g.group,g.weight) for g in v.groups) for v in mesh.vertices];bones={b.name:(b.head_local.copy(),b.tail_local.copy()) for b in rig.data.bones}
 hands={b.name for s in ('L','R') for b in [rig.data.bones['wrist.'+s],*rig.data.bones['wrist.'+s].children_recursive]}
 params={}
 for s in ('L','R'):
  shoulder=bones['upperarm01.'+s][0];elbow=bones['lowerarm01.'+s][0];wrist=bones['wrist.'+s][0];params[s]=(shoulder,elbow,wrist)
 def displacement(name,co):
  s=name[-1:]
  if s not in params or not name.endswith('.'+s):return Vector()
  shoulder,elbow,wrist=params[s];upper=elbow-shoulder;lower=wrist-elbow
  if name.startswith('upperarm'):
   t=max(0,min(1,(co-shoulder).dot(upper)/upper.length_squared));return a.length*t*upper
  if name.startswith('lowerarm'):
   t=max(0,min(1,(co-elbow).dot(lower)/lower.length_squared));return a.length*(upper+t*lower)
  if name in hands:return a.length*(upper+lower)
  return Vector()
 delta=[sum((displacement(body.vertex_groups[g].name,co)*w for g,w in row),Vector()) for co,row in zip(original,weights)]
 for v,d in zip(mesh.vertices,delta):v.co+=d
 for k in mesh.shape_keys.key_blocks:
  for i,p in enumerate(k.data):p.co=shapes[k.name][i]+delta[i]
 bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
 for b in rig.data.edit_bones:
  h,t=bones[b.name];b.head=h+displacement(b.name,h);b.tail=t+displacement(b.name,t)
 bpy.ops.object.mode_set(mode='OBJECT');mesh.update();bpy.context.view_layer.update()
 basis=mesh.shape_keys.key_blocks['Basis'];err=max(((p.co-basis.data[i].co)-(shapes[k.name][i]-shapes['Basis'][i])).length for k in mesh.shape_keys.key_blocks for i,p in enumerate(k.data));assert err<1e-6
 assert weights==[tuple((g.group,g.weight) for g in v.groups) for v in mesh.vertices];assert all(c.driver.is_valid for c in mesh.shape_keys.animation_data.drivers)
 ratios={}
 for s,(sh,el,wr) in params.items():
  n=[rig.data.bones[x+'.'+s].head_local for x in ('upperarm01','lowerarm01','wrist')];ratios[s]=[(n[1]-n[0]).length/(el-sh).length,(n[2]-n[1]).length/(wr-el).length];assert all(abs(x-(1+a.length))<1e-5 for x in ratios[s])
 report={'errors':[],'warnings':[],'source':str(source),'source_sha256':before,'arm_length_fraction':a.length,'segment_ratios':ratios,'changed_vertices':sum(d.length>1e-8 for d in delta),'maximum_displacement_m':max(d.length for d in delta),'relative_key_error_m':err,'weights_unchanged':True,'scope':'Rig and skin arm-length extension only; fixed pose, cameras, reference, material and scoring unchanged.'}
 check_original_mesh(body,report);check_armature_weights(body,report);assert not report['errors'],report['errors'];assert report['original_mesh']['connected_component_count']==1 and report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire']==0
 bpy.context.scene['version']='V39 rig-consistent arm length study';bpy.context.scene['approved_for_animation']=False;bpy.context.scene.cycles.device='CPU';out.parent.mkdir(parents=True,exist_ok=True);bpy.ops.wm.save_as_mainfile(filepath=str(out));assert digest(source)==before
 report.update(candidate=str(out),candidate_sha256=digest(out),source_unchanged=True,builder_sha256=digest(__file__));out.with_suffix('.json').write_text(json.dumps(report,indent=2));print('V39_CANDIDATE',out,flush=True)
if __name__=='__main__':main()
