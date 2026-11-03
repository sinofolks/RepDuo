"""Small, bounded shoulder/arm and surface-plane refinements of V4 work."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Quaternion

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_green_body import smoothstep
from body_geometry_v2 import _rotate
from stance_v3 import plant_feet
from validate_green_body import check_original_mesh, check_armature_weights

DEFAULTS = {'left_arm_in': 0, 'left_forearm_out': 0, 'right_arm_out': 0,
            'right_forearm_in': 0, 'axilla_fill': 0, 'nose_plane': 0, 'chin_plane': 0,
            'forearm_extra': 0, 'foot_yaw_delta_R': 0, 'foot_yaw_delta_L': 0}


def gaussian(v, c, s):
    return math.exp(-.5*((v-c)/s)**2)


def refine(body, rig, p):
    original = [v.co.copy() for v in body.data.vertices]
    weights = [tuple((g.group, g.weight) for g in v.groups) for v in body.data.vertices]
    for v in body.data.vertices:
        x, y, z = v.co
        front = 1-smoothstep(-.095, -.04, y)
        if 1.25 < z < 1.47 and abs(x) < .23:
            # Symmetric broad pectoral/axillary fold, not a one-view patch.
            w = gaussian(abs(x), .151, .037) * gaussian(z, 1.357, .045) * front
            w *= smoothstep(1.25, 1.28, z)*(1-smoothstep(1.44, 1.47, z))
            v.co.y -= p['axilla_fill']*w
        if 1.61 < z < 1.745:
            nose = gaussian(x, 0, .013)*gaussian(z, 1.682, .017)
            chin = gaussian(x, 0, .028)*gaussian(z, 1.628, .012)
            fade = smoothstep(1.61, 1.62, z)*(1-smoothstep(1.73, 1.745, z))
            v.co.y -= (p['nose_plane']*nose+p['chin_plane']*chin)*front*fade
    for side in ('L', 'R'):
        start = rig.data.bones['lowerarm01.'+side].head_local
        end = rig.data.bones['wrist.'+side].head_local
        axis = end-start
        for v in body.data.vertices:
            offset = v.co-start
            t = offset.dot(axis)/axis.length_squared
            radial = offset-axis*t
            if .04 < t < .94 and radial.length < .075:
                w = smoothstep(.04, .23, t)*(1-smoothstep(.70, .94, t))
                w *= 1-smoothstep(.05, .075, radial.length)
                v.co += radial*p['forearm_extra']*w
    body.data.update()
    for name, degrees in [('upperarm01.L', p['left_arm_in']),
                           ('lowerarm01.L', -p['left_forearm_out']),
                           ('upperarm01.R', p['right_arm_out']),
                           ('lowerarm01.R', -p['right_forearm_in'])]:
        _rotate(rig.pose.bones[name], Quaternion((0, 1, 0), math.radians(degrees)))
    support = None
    if p['foot_yaw_delta_R'] or p['foot_yaw_delta_L']:
        for side in ('R', 'L'):
            _rotate(rig.pose.bones['foot.'+side], Quaternion((0, 0, 1), math.radians(p['foot_yaw_delta_'+side])))
        support = plant_feet(body, rig)
        assert all(-.0002 <= z-support['floor_z_m'] <= .002 for z in support['minimum_z_m'].values()), support
    assert weights == [tuple((g.group, g.weight) for g in v.groups) for v in body.data.vertices]
    assert all(tuple(v.co) == tuple(original[v.index]) for v in body.data.vertices if original[v.index].z <= 1.0)
    return {'max_rest_displacement_m': max((v.co-original[v.index]).length for v in body.data.vertices),
            'changed_vertices': sum(v.co != original[v.index] for v in body.data.vertices),
            'lower_body_mesh_unchanged': True, 'weights_preserved': True, 'recomputed_support': support}


def main():
    assert bpy.app.background
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--source', type=Path, default=ROOT/'GreenBody-v4-work.blend')
    parser.add_argument('--params-json', default='{}')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    out, source = args.out.resolve(), args.source.resolve()
    if out.exists() or out.with_suffix('.json').exists():
        raise ValueError('Refusing to overwrite candidate or evidence')
    supplied = json.loads(args.params_json)
    if set(supplied)-set(DEFAULTS):
        raise ValueError('Unknown study parameters')
    p = {**DEFAULTS, **supplied}
    for key, value in p.items():
        limit = .25 if key == 'forearm_extra' else (.012 if key.endswith(('fill', 'plane')) else 12)
        if key.startswith('foot_yaw_delta_'):
            limit = 25
        if not isinstance(value, (int, float)) or not math.isfinite(value) or abs(value) > limit:
            raise ValueError(f'Parameter outside bounded range: {key}')
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    body, rig = bpy.data.objects['GreenBody'], bpy.data.objects['GB_ReviewArmature']
    report = {'parameters': p, 'geometry': refine(body, rig, p), 'errors': [], 'warnings': []}
    check_original_mesh(body, report)
    check_armature_weights(body, report)
    assert not report['errors'], report['errors']
    assert report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire'] == 0
    assert report['original_mesh']['connected_component_count'] == 1
    scene = bpy.context.scene
    scene['version'] = 'Green Body V5 shoulder and surface study'
    scene['approved_for_animation'] = False
    scene['v5_parameters'] = json.dumps(p, sort_keys=True)
    scene['v5_builder_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    scene.cycles.device = 'CPU'
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert hashlib.sha256(source.read_bytes()).hexdigest() == digest
    report.update({'source': str(source), 'source_sha256': digest, 'source_unchanged': True,
                   'candidate': str(out), 'candidate_sha256': hashlib.sha256(out.read_bytes()).hexdigest()})
    out.with_suffix('.json').write_text(json.dumps(report, indent=2))
    print('V5_CANDIDATE', out, flush=True)


if __name__ == '__main__':
    main()
