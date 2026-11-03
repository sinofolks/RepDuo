"""Actual hand closeups and bone projection, source file read-only."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector


def main():
    assert bpy.app.background
    p=argparse.ArgumentParser(); p.add_argument('--out',type=Path,required=True)
    args=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    source=Path(bpy.data.filepath)
    source_hash=hashlib.sha256(source.read_bytes()).hexdigest()
    out=args.out.resolve(); out.mkdir(parents=True,exist_ok=False)
    rig=bpy.data.objects['GB_ReviewArmature']
    scene=bpy.context.scene
    report={'source':str(source),'source_sha256':source_hash,'hands':{}}
    for side,sign in [('L',1),('R',-1)]:
        bones={name:rig.matrix_world@rig.pose.bones[name+'.'+side].tail for name in ['finger1-3','finger2-3','finger3-3','finger4-3','finger5-3']}
        wrist=rig.matrix_world@rig.pose.bones['wrist.'+side].head
        report['hands'][side]={'wrist':list(wrist),'fingertips':{n:list(v) for n,v in bones.items()},
                              'thumb_more_medial_than_pinky':sign*bones['finger1-3'].x < sign*bones['finger5-3'].x}
    side='R'
    wrist=rig.matrix_world@rig.pose.bones['wrist.'+side].head
    middle=rig.matrix_world@rig.pose.bones['finger3-3.'+side].tail
    center=(wrist+middle)*.5
    camera=bpy.data.objects['GB_Camera_Hero'].copy(); camera.data=camera.data.copy(); scene.collection.objects.link(camera)
    camera.data.type='ORTHO'; camera.data.ortho_scale=.29
    scene.camera=camera
    scene.render.resolution_x=800; scene.render.resolution_y=800; scene.render.resolution_percentage=100
    scene.cycles.device='CPU'; scene.cycles.samples=32
    for name,offset in [('front',(0,-5,0)),('back',(0,5,0)),('side',(-5,0,0))]:
        camera.location=center+Vector(offset)
        camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(out/(name+'.png'))
        bpy.ops.render.render(write_still=True)
    report['source_unchanged']=hashlib.sha256(source.read_bytes()).hexdigest()==source_hash
    assert report['source_unchanged']
    (out/'inspection.json').write_text(json.dumps(report,indent=2))
    print('HAND_INSPECTION',out,flush=True)


if __name__=='__main__': main()
