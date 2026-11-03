"""Uniform native pigment/BRDF study; geometry, rig, lighting and cameras fixed."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import bpy

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
sys.path.insert(0, str(ROOT / 'calibration'))
from studio import _hex_linear
from render_candidate import geometry_state, pose_state, lighting_state, canonical_hash, material_state


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    assert bpy.app.background
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=ROOT / 'GreenBody-v18-work.blend')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--color', default='BEE83B')
    parser.add_argument('--roughness', type=float, default=.48)
    parser.add_argument('--specular', type=float, default=.24)
    parser.add_argument('--subsurface', type=float, default=0.)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    assert re.fullmatch('[0-9a-fA-F]{6}', args.color)
    assert .2 <= args.roughness <= .8 and 0 <= args.specular <= .5 and 0 <= args.subsurface <= .1
    source, out = args.source.resolve(), args.out.resolve()
    assert not out.exists() and not out.with_suffix('.json').exists()
    source_hash = digest(source)
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    body, scene = bpy.data.objects['GreenBody'], bpy.context.scene

    def state():
        pose, rig = pose_state(body)
        return {'geometry': geometry_state(body), 'pose': pose, 'lighting': lighting_state(scene),
                'cameras': {o.name: [list(row) for row in o.matrix_world] for o in scene.objects if o.type == 'CAMERA'},
                'shape_keys': {k.name: canonical_hash([tuple(p.co) for p in k.data]) for k in body.data.shape_keys.key_blocks},
                'weights': canonical_hash([[(g.group, g.weight) for g in v.groups] for v in body.data.vertices]),
                'rest_bones': canonical_hash({b.name: [list(row) for row in b.matrix_local] for b in rig.data.bones})}

    before = state()
    original_material = material_state(body)
    assert len(body.data.materials) == 1
    material = body.data.materials[0].copy()
    material.name = 'GB_V19_UniformPigment_' + args.color.upper()
    shader = next(n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    values = {'Base Color': _hex_linear('#' + args.color), 'Roughness': args.roughness,
              'Specular IOR Level': args.specular, 'Subsurface Weight': args.subsurface}
    for name, value in values.items():
        assert not shader.inputs[name].is_linked
        shader.inputs[name].default_value = value
    material.diffuse_color = values['Base Color']
    body.data.materials[0] = material
    bpy.context.view_layer.update()
    after = state()
    assert before == after, 'Material study unexpectedly changed geometry/pose/studio'
    assert all(c.driver.is_valid for c in body.data.shape_keys.animation_data.drivers)
    scene['version'] = 'V19 uniform native pigment/BRDF study'
    scene['approved_for_animation'] = False
    scene.cycles.device = 'CPU'
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert digest(source) == source_hash
    report = {'source': str(source), 'source_sha256': source_hash, 'source_unchanged': True,
              'candidate': str(out), 'candidate_sha256': digest(out), 'builder_sha256': digest(__file__),
              'parameters': {'srgb_hex': args.color.upper(), 'roughness': args.roughness,
                             'specular': args.specular, 'subsurface': args.subsurface},
              'unchanged_state_sha256': canonical_hash(before),
              'geometry_rig_keys_weights_studio_unchanged': True,
              'original_material': original_material, 'candidate_material': material_state(body),
              'scope': 'One uniform native material, no image warp, view-specific shader or emission compensation.'}
    out.with_suffix('.json').write_text(json.dumps(report, indent=2))
    print('V19_CANDIDATE', out, flush=True)


if __name__ == '__main__':
    main()
