"""Read-only actual native-material foot closeups, not calibration captures."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import bpy
from mathutils import Vector


def main():
    assert bpy.app.background
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    source = Path(bpy.data.filepath)
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    scene = bpy.context.scene
    rig = bpy.data.objects['GB_ReviewArmature']
    foot = rig.matrix_world @ rig.pose.bones['foot.L'].head
    toe = rig.matrix_world @ rig.pose.bones['toe3-3.L'].tail
    center = (foot + toe) * .5
    camera = bpy.data.objects['GB_Camera_Hero'].copy()
    camera.data = camera.data.copy()
    scene.collection.objects.link(camera)
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = .36
    scene.camera = camera
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 24
    scene.render.resolution_x = scene.render.resolution_y = 600
    scene.render.resolution_percentage = 100
    for name, offset in [('side', (5, 0, 0)), ('dorsal', (1, -4, 3))]:
        camera.location = center + Vector(offset)
        camera.rotation_euler = (center-camera.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = str(out / (name + '.png'))
        bpy.ops.render.render(write_still=True)
    assert hashlib.sha256(source.read_bytes()).hexdigest() == before
    (out / 'inspection.json').write_text(json.dumps({'source': str(source), 'source_sha256': before,
                                                   'source_unchanged': True, 'center': list(center)}, indent=2))
    print('FOOT_INSPECTION', out, flush=True)


if __name__ == '__main__':
    main()
