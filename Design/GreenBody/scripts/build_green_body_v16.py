"""Local, shape-key-safe surface fairing. Never automatic acceptance."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from validate_green_body import check_original_mesh, check_armature_weights


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    assert bpy.app.background
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=ROOT / 'GreenBody-v15.1-work.blend')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--iterations', type=int, default=10)
    parser.add_argument('--region', choices=('hands', 'toes', 'head'), default='hands')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    assert 1 <= args.iterations <= 30
    source, out = args.source.resolve(), args.out.resolve()
    assert not out.exists() and not out.with_suffix('.json').exists()
    source_hash = digest(source)
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    body = bpy.data.objects['GreenBody']
    original = np.array([tuple(v.co) for v in body.data.vertices])
    weights = [tuple((g.group, g.weight) for g in v.groups) for v in body.data.vertices]
    shapes = {key.name: np.array([tuple(p.co) for p in key.data])
              for key in body.data.shape_keys.key_blocks}
    if args.region == 'head':
        mask = np.clip((original[:, 2] - 1.50) / .12, 0, 1)
    else:
        prefix = 'finger' if args.region == 'hands' else 'toe'
        groups = {g.index for g in body.vertex_groups if g.name.startswith(prefix)}
        assert groups
        weight = np.array([sum(w for g, w in row if g in groups) for row in weights])
        mask = np.clip((weight - .05) / .8, 0, 1)
    mask = mask * mask * (3 - 2 * mask)
    edges = np.array([tuple(e.vertices) for e in body.data.edges])
    src = np.r_[edges[:, 0], edges[:, 1]]
    dst = np.r_[edges[:, 1], edges[:, 0]]
    degree = np.bincount(src, minlength=len(original))
    points = original.copy()
    # Two-pass Taubin-style filter reduces shrinkage; explicit displacement cap
    # bounds the study, not a claim of volume conservation or anatomical QA.
    for _ in range(args.iterations):
        for coefficient in (.45, -.47):
            average = np.zeros_like(points)
            np.add.at(average, src, points[dst])
            average /= np.maximum(degree[:, None], 1)
            points += coefficient * mask[:, None] * (average - points)
    delta = points - original
    length = np.linalg.norm(delta, axis=1)
    delta *= np.minimum(1, .004 / np.maximum(length, 1e-12))[:, None]
    assert np.array_equal(delta[mask == 0], np.zeros_like(delta[mask == 0]))
    for v, co in zip(body.data.vertices, original + delta):
        v.co = co
    for key in body.data.shape_keys.key_blocks:
        for point, co in zip(key.data, shapes[key.name] + delta):
            point.co = co
    body.data.update()
    bpy.context.view_layer.update()
    basis = np.array([tuple(p.co) for p in body.data.shape_keys.key_blocks['Basis'].data])
    error = max(float(np.max(np.abs(
        np.array([tuple(p.co) for p in key.data]) - basis -
        (shapes[key.name] - shapes['Basis'])))) for key in body.data.shape_keys.key_blocks)
    assert error < 1e-6
    assert weights == [tuple((g.group, g.weight) for g in v.groups) for v in body.data.vertices]
    report = {'errors': [], 'warnings': [], 'iterations': args.iterations, 'region': args.region,
              'changed_vertices': int(np.count_nonzero(np.linalg.norm(delta, axis=1) > 1e-8)),
              'max_displacement_m': float(np.max(np.linalg.norm(delta, axis=1))),
              'shape_delta_error_m': error, 'weights_unchanged': True,
              'source': str(source), 'source_sha256': source_hash}
    check_original_mesh(body, report)
    check_armature_weights(body, report)
    assert not report['errors'], report['errors']
    assert report['original_mesh']['connected_component_count'] == 1
    assert report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire'] == 0
    assert all(c.driver.is_valid for c in body.data.shape_keys.animation_data.drivers)
    bpy.context.scene['version'] = 'Local ' + args.region + ' fairing study'
    bpy.context.scene['approved_for_animation'] = False
    bpy.context.scene.cycles.device = 'CPU'
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert digest(source) == source_hash
    report.update(candidate=str(out), candidate_sha256=digest(out), source_unchanged=True,
                  builder_sha256=digest(__file__))
    out.with_suffix('.json').write_text(json.dumps(report, indent=2))
    print('V16_CANDIDATE', out, flush=True)


if __name__ == '__main__':
    main()
