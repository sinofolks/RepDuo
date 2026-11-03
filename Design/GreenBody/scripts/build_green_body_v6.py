"""V6: bounded posterior-cranium fairing and local deformation studies.

Preserve the original model, all faces and bone weights. New non-bone vertex
groups are explicitly modifier masks, never replacement skin weights.
"""
import argparse
from collections import defaultdict
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
from build_green_body import smoothstep
from validate_green_body import check_original_mesh, check_armature_weights


def fair_posterior(body, strength):
    mesh = body.data
    original = [v.co.copy() for v in mesh.vertices]
    rows = defaultdict(list)
    for v in mesh.vertices:
        if 1.59 < v.co.z < 1.74:
            rows[round(v.co.z, 5)].append(v.index)
    profile = sorted((z, max(original[i].y for i in indices)) for z, indices in rows.items())
    zs, ys = np.array(profile).T
    deltas = {}
    for z, back in profile:
        # Locally weighted quadratic regression of the ACTUAL rest-space
        # posterior profile removes its short curvature plateau. This is a
        # geometry fairing operation, not smoothing of a rendered image.
        t = (zs-z)/.018
        w = np.exp(-.5*t*t)
        design = np.column_stack((np.ones_like(t), t, t*t))
        fit = np.linalg.lstsq(design*np.sqrt(w[:, None]), ys*np.sqrt(w), rcond=None)[0]
        fade = smoothstep(1.608, 1.631, z)*(1-smoothstep(1.682, 1.709, z))
        deltas[z] = float(np.clip(fit[0]-back, -.003, .003))*fade*strength
    for z, indices in rows.items():
        for i in indices:
            x, y, _ = original[i]
            rear = smoothstep(-.027, .045, y)
            ear_protection = 1-smoothstep(.068, .082, abs(x))
            mesh.vertices[i].co.y += deltas[z]*rear*ear_protection
    mesh.update()
    after = [(z, max(mesh.vertices[i].co.y for i in rows[z])) for z, _ in profile]
    def roughness(points):
        z, y = np.array(points).T
        curvature = np.gradient(np.gradient(y, z), z)
        change = np.gradient(curvature, z)
        region = (z > 1.633) & (z < 1.680)
        return float(np.sqrt(np.mean(change[region]**2)))
    assert all(tuple(v.co) == tuple(original[v.index]) for v in mesh.vertices if original[v.index].z <= 1.608)
    return {'max_rest_displacement_m': max((v.co-original[v.index]).length for v in mesh.vertices),
            'changed_vertices': sum(v.co != original[v.index] for v in mesh.vertices),
            'posterior_profile_before': profile, 'posterior_profile_after': after,
            'profile_curvature_change_rms_before': roughness(profile),
            'profile_curvature_change_rms_after': roughness(after),
            'profile_metric_scope': 'Local posterior centerline smoothness only, not reference likeness or global quality'}


def joint_smoothing(body, rig, factor, iterations, method):
    if factor == 0:
        return {'enabled': False}
    group = body.vertex_groups.new(name='GB_QA_JointFairing_Mask')
    centers = [(rig.data.bones['lowerleg01.'+side].head_local, .13, .20)
               for side in ('L', 'R')]
    centers += [(rig.data.bones['upperarm01.'+side].head_local, .105, .175)
                for side in ('L', 'R')]
    count = 0
    for v in body.data.vertices:
        weight = max(1-smoothstep(inner, outer, (v.co-center).length)
                     for center, inner, outer in centers)
        if weight > .0001:
            group.add([v.index], weight, 'REPLACE')
            count += 1
    mod = body.modifiers.new('Joint fairing study — original shape retained', 'CORRECTIVE_SMOOTH')
    mod.factor = factor
    mod.iterations = iterations
    mod.smooth_type = 'LENGTH_WEIGHTED'
    mod.rest_source = 'ORCO'
    mod.use_only_smooth = method == 'surface'
    mod.vertex_group = group.name
    # Corrective smoothing needs the deformed low-resolution cage, before
    # presentation subdivision. The existing subtle polish stays unchanged.
    src = list(body.modifiers).index(mod)
    target = next(i for i, m in enumerate(body.modifiers) if m.type == 'SUBSURF')
    body.modifiers.move(src, target)
    return {'enabled': True, 'factor': factor, 'iterations': iterations,
            'mask_vertices': count, 'mask_group': group.name,
            'method': method,
            'original_shape_compensation': not mod.use_only_smooth,
            'notes': 'Length-weighted bounded joint mask; surface mode also changes the neutral evaluated shape'}


def main():
    assert bpy.app.background, 'Run in an independent background Blender'
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=ROOT/'GreenBody-v5-work.blend')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--head-strength', type=float, default=1)
    parser.add_argument('--joint-factor', type=float, default=0)
    parser.add_argument('--joint-iterations', type=int, default=12)
    parser.add_argument('--joint-method', choices=('corrective', 'surface'), default='corrective')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    for value in (args.head_strength, args.joint_factor):
        if not math.isfinite(value) or not 0 <= value <= 1:
            raise ValueError('Study strengths must be finite and within [0,1]')
    if not 1 <= args.joint_iterations <= 40:
        raise ValueError('Iterations outside [1,40]')
    source, out = args.source.resolve(), args.out.resolve()
    if out.exists() or out.with_suffix('.json').exists():
        raise ValueError('Refusing to overwrite any existing candidate or evidence')
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    body, rig = bpy.data.objects['GreenBody'], bpy.data.objects['GB_ReviewArmature']
    original_group_count = len(body.vertex_groups)
    original_weights = [tuple((g.group, g.weight) for g in v.groups) for v in body.data.vertices]
    report = {'parameters': {'head_strength': args.head_strength, 'joint_factor': args.joint_factor,
                             'joint_iterations': args.joint_iterations,
                             'joint_method': args.joint_method}, 'errors': [], 'warnings': []}
    report['head_geometry'] = fair_posterior(body, args.head_strength)
    report['joint_modifier'] = joint_smoothing(body, rig, args.joint_factor, args.joint_iterations, args.joint_method)
    assert original_weights == [tuple((g.group, g.weight) for g in v.groups if g.group < original_group_count)
                                for v in body.data.vertices]
    report['original_bone_weights_unchanged'] = True
    check_original_mesh(body, report)
    check_armature_weights(body, report)
    assert not report['errors'], report['errors']
    assert report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire'] == 0
    assert report['original_mesh']['connected_component_count'] == 1
    scene = bpy.context.scene
    scene['version'] = 'Green Body V6 surface and deformation study'
    scene['approved_for_animation'] = False
    scene['v6_parameters'] = json.dumps(report['parameters'], sort_keys=True)
    scene['v6_builder_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    scene.cycles.device = 'CPU'
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert hashlib.sha256(source.read_bytes()).hexdigest() == digest
    report.update({'source': str(source), 'source_sha256': digest, 'source_unchanged': True,
                   'candidate': str(out), 'candidate_sha256': hashlib.sha256(out.read_bytes()).hexdigest()})
    out.with_suffix('.json').write_text(json.dumps(report, indent=2))
    print('V6_CANDIDATE', out, flush=True)


if __name__ == '__main__':
    main()
