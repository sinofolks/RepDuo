"""Render a read-only squat loop from a GreenBody work model."""
import argparse, hashlib, math, sys
from pathlib import Path
import bpy
from mathutils import Matrix, Vector

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from review_poses import reset, update
from review_poses_v2 import deep_squat, evaluated_points

def digest(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('--blend',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--frames',type=int,default=48)
 a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);source,out=a.blend.resolve(),a.out.resolve();assert source.is_file() and not out.exists();before=digest(source)
 bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False);scene=bpy.context.scene;body=bpy.data.objects['GreenBody'];rig=next(m.object for m in body.modifiers if m.type=='ARMATURE')
 reset(rig);neutral={b.name:b.matrix_basis.copy() for b in rig.pose.bones};deep_squat(rig);target={b.name:b.matrix_basis.copy() for b in rig.pose.bones};reset(rig)
 # Fixed, deliberately roomy camera: every interpolation remains visible.
 cam=bpy.data.objects['GB_Camera_Hero'];cam.location=Vector((-5.0,-3.2,1.25));cam.data.ortho_scale=2.05;cam.rotation_euler=(Vector((0,0,0.92))-cam.location).to_track_quat('-Z','Y').to_euler();scene.camera=cam
 out.parent.mkdir(parents=True,exist_ok=True);frames=out.parent/(out.stem+'-frames');frames.mkdir()
 scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=512;scene.render.resolution_y=512;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.fps=24;scene.render.filepath=str(frames/'frame_');scene.render.film_transparent=False
 for f in range(1,a.frames+1):
  t=.5-.5*math.cos(2*math.pi*(f-1)/(a.frames-1))
  for b in rig.pose.bones:
   p0,r0,s0=neutral[b.name].decompose();p1,r1,s1=target[b.name].decompose();b.matrix_basis=Matrix.LocRotScale(p0.lerp(p1,t),r0.slerp(r1,t),s0.lerp(s1,t))
   b.keyframe_insert(data_path='location',frame=f);b.keyframe_insert(data_path='rotation_quaternion',frame=f);b.keyframe_insert(data_path='scale',frame=f)
  update();scene.frame_set(f)
 scene.frame_start=1;scene.frame_end=a.frames;scene['animation_preview_only']=True;scene['approved_for_animation']=False
 bpy.ops.render.render(animation=True);assert digest(source)==before;print(out,flush=True)
if __name__=='__main__':main()
