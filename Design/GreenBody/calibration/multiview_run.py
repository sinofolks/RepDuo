"""Three-view orchestration using the unchanged single-view evidence engine.

The approved turnaround has a separate protocol per view. Never combine it
with old hero-view scores or silently omit a missing/poor view.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
MULTI = ROOT/'multiview'
REFERENCES = ROOT/'multiview/references'
VIEWS = ('front', 'side', 'back')
BLENDER = '/Applications/Blender.app/Contents/MacOS/Blender'


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def aggregate_results(results):
    if set(results) != set(VIEWS):
        raise ValueError('Exactly front, side and back are required; no omitted views')
    sources, scores = set(), {}
    geometries, poses, materials, reference_series = set(), set(), set(), set()
    for view in VIEWS:
        result = results[view]
        if str(result['score_status']).startswith(('invalid', 'incomplete')) or result['landmark_coverage'] != 1:
            raise ValueError(f'Incomplete evidence for {view}')
        score = result['composite_score']
        if not isinstance(score, (int, float)) or not math.isfinite(score) or not 0 <= score <= 100:
            raise ValueError('Invalid view score')
        cap = result['provenance']['capture']
        if cap['status'] != 'complete' or not cap['source_unchanged']:
            raise ValueError('Failed or mutated-source capture')
        if not cap.get('native_appearance') or cap['track'] != 'native-material_fixed-studio':
            raise ValueError('This multiview protocol requires native material')
        reference = result['provenance']['reference']['config']
        if reference['view'] != 'approved-turnaround-'+view:
            raise ValueError('Result assigned to the wrong reference view')
        if reference['design_approval']['status'] != 'user_approved':
            raise ValueError('Unapproved reference design')
        reference_series.add(reference.get('reference_series','turnaround-v1'))
        sources.add(cap['source_blend_sha256_before'])
        for key, target in [('geometry_hash', geometries), ('pose_hash', poses), ('material_hash', materials)]:
            if not cap.get(key):
                raise ValueError('Missing shared-state evidence: '+key)
            target.add(cap[key])
        if cap['source_blend_sha256_before'] != cap['source_blend_sha256_after']:
            raise ValueError('Source hash mismatch')
        scores[view] = float(score)
    if len(sources) != 1:
        raise ValueError('All views must come from the identical canonical model')
    if len(reference_series) != 1:
        raise ValueError('Cannot mix harmonized and original reference views')
    if any(len(values) != 1 for values in (geometries, poses, materials)):
        raise ValueError('Geometry, pose and material must remain identical across all views')
    return {'schema': 'greenbody-three-view-agreement-v1',
            'status': 'provisional_reference_agreement', 'scores': scores,
            'equal_view_mean': sum(scores.values())/3, 'minimum_view_score': min(scores.values()),
            'numeric_99_target_met_in_every_view': all(s >= 99 for s in scores.values()),
            'automatic_model_approval': False, 'source_canonical_sha256': sources.pop(),
            'shared_state_verified': {'geometry_hash': geometries.pop(), 'pose_hash': poses.pop(),
                                      'material_hash': materials.pop()},
            'protocols': {v: results[v]['protocol_id'] for v in VIEWS},
            'interpretation': 'Three reference projections, not a certified 3D reconstruction percentage. Inspect per-view regions, actual geometry and deformation before approval.'}


def run_logged(command, path):
    with path.open('x') as stream:
        completed = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT)
    if completed.returncode:
        raise RuntimeError(f'Command failed ({completed.returncode}); see {path}')


def measure_view(view, model, directory, label):
    capture = directory/view
    run_logged([BLENDER, '--background', '--factory-startup', '--python-exit-code', '1',
                '--python', str(ROOT/'render_candidate.py'), '--', '--blend', str(model),
                '--out', str(capture), '--profile', str(MULTI/'profiles'/f'{view}.json'),
                '--native-appearance'], directory/f'{view}-capture.log')
    # Independent evaluator subprocess prevents shared mutable module state.
    before = set((MULTI/'runs').glob('*/result.json'))
    run_logged([sys.executable, str(ROOT/'calibrate.py'), 'evaluate', '--reference',
                str(REFERENCES/view), '--capture', str(capture), '--label', label+'-'+view,
                '--out', str(MULTI/'runs')], directory/f'{view}-evaluate.log')
    paths = []
    for p in set((MULTI/'runs').glob('*/result.json'))-before:
        data = json.loads(p.read_text())
        if (data['label'] == label+'-'+view
                and data['provenance']['capture']['source_blend'] == str(model)):
            paths.append(p)
    if len(paths) != 1:
        raise RuntimeError('Could not uniquely locate the new view measurement')
    path = paths[0]
    return view, json.loads(path.read_text()), path


def main():
    global MULTI, REFERENCES
    parser = argparse.ArgumentParser()
    parser.add_argument('--blend', type=Path, required=True)
    parser.add_argument('--label', required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--pose-version', choices=('v1','v2'), default='v1')
    parser.add_argument('--reference-version', choices=('v1','v3','v4'), default='v1')
    args = parser.parse_args()
    if args.pose_version == 'v2':
        MULTI = ROOT/'multiview-pose-v2'
    if args.reference_version in ('v3', 'v4'):
        if args.pose_version != 'v2':
            raise ValueError('Reference v3/v4 is configured only for pose v2')
        MULTI = ROOT/f'multiview-reference-{args.reference_version}'
        REFERENCES = MULTI/'references'
    preparer = 'prepare_turnaround_pose_v2.py' if args.pose_version == 'v2' else 'prepare_turnaround_pose.py'
    runner_hash = digest(__file__)
    source, out = args.blend.resolve(), args.out.resolve()
    if not source.is_file():
        raise ValueError('Source model missing')
    out.mkdir(parents=True, exist_ok=False)
    model = out/'canonical.blend'
    run_logged([BLENDER, '--background', '--factory-startup', '--python-exit-code', '1', '--python',
                str(ROOT.parent/'scripts'/preparer), '--', '--blend', str(source),
                '--out', str(model)], out/'prepare.log')
    results, paths = {}, {}
    with ThreadPoolExecutor(max_workers=2) as executor:
        pending = [executor.submit(measure_view, v, model, out, args.label) for v in VIEWS]
        for task in as_completed(pending):
            view, result, path = task.result()
            results[view], paths[view] = result, path
            print(json.dumps({'view': view, 'score': result['composite_score'], 'result': str(path)}), flush=True)
    preparation = json.loads(model.with_suffix('.json').read_text())
    if digest(source) != preparation['source_sha256']:
        raise RuntimeError('Original source changed after canonical preparation; do not label this run as current-source evidence')
    if digest(__file__) != runner_hash:
        raise RuntimeError('Runner code changed while running; retain evidence but do not certify the run')
    summary = aggregate_results(results)
    summary.update({'label': args.label, 'created_at': datetime.now(timezone.utc).isoformat(),
                    'original_model': str(source), 'original_model_sha256': digest(source),
                    'canonical_model': str(model), 'preparation': preparation,
                    'view_results': {v: {'path': str(paths[v]), 'sha256': digest(paths[v])} for v in VIEWS},
                    'runner_sha256': runner_hash, 'pose_version': args.pose_version,
                    'reference_version':args.reference_version})
    (out/'summary.json').write_text(json.dumps(summary, indent=2, ensure_ascii=False, allow_nan=False))
    print(json.dumps({'summary': str(out/'summary.json'), 'mean': summary['equal_view_mean'],
                      'minimum': summary['minimum_view_score']}), flush=True)
    # Reuse the existing offline viewer; every entry is explicitly view-specific.
    run_logged([sys.executable, str(ROOT/'calibrate.py'), 'report', '--runs', str(MULTI/'runs'),
                '--out', str(out/'report.html')], out/'report.log')


if __name__ == '__main__':
    main()
