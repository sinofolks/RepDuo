"""Measure approved head silhouettes for a bounded real-geometry sculpt.

This does not edit any reference/render or change the calibration protocol.
Front and back jointly constrain width; side constrains sagittal contours.
"""
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter1d

ROOT = Path(__file__).resolve().parents[1]
MULTI = ROOT/'calibration/multiview'
OUT = ROOT/'v8-head-sections.json'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def contours(path):
    mask = np.array(Image.open(path).convert('L')) > 127
    sections = []
    for row in range(40, 191):
        occupied = np.flatnonzero(mask[row])
        if not len(occupied):
            raise ValueError(f'Missing silhouette at row {row}')
        sections.append([occupied.min(), occupied.max()])
    return gaussian_filter1d(np.array(sections, dtype=float), sigma=2.5, axis=0, mode='nearest')


def main():
    if OUT.exists():
        raise ValueError('Refusing to overwrite measured sculpt input')
    runs = {v: next((MULTI/'runs').glob('*-V7-body-'+v+'/result.json')) for v in ('front','side','back')}
    results = {v: json.loads(p.read_text()) for v,p in runs.items()}
    references = {v: MULTI/'references'/v/'reference_mask.png' for v in runs}
    candidates = {v: p.parent/'candidate_mask.png' for v,p in runs.items()}
    ref = {v: contours(p) for v,p in references.items()}
    cur = {v: contours(p) for v,p in candidates.items()}
    target_width = sum(ref[v][:,1]-ref[v][:,0]+1 for v in ('front','back'))/2
    source_width = sum(cur[v][:,1]-cur[v][:,0]+1 for v in ('front','back'))/2
    width_scale = np.clip(target_width/source_width, .80, 1.45)
    side_delta = np.clip(ref['side']-cur['side'], -20, 20)
    report = {'schema':'greenbody-v8-head-section-sculpt-v1',
              'source_model_sha256':'6418619612c1fc4aa7bdb2af1033ea9d6009e1ae52d144690a8bda59994c54df',
              'reference_sha256':digest(ROOT/'reference/green-body-turnaround-v1-candidate.png'),
              'measurement_script_sha256':digest(Path(__file__)),
              'runs':{v:{'path':str(p),'sha256':digest(p)} for v,p in runs.items()},
              'masks':{kind:{v:{'path':str(p),'sha256':digest(p)} for v,p in paths.items()}
                       for kind,paths in [('reference',references),('candidate',candidates)]},
              'side_alignment':results['side']['alignment']['candidate'],
              'rows':list(range(40,191)), 'width_scale':width_scale.tolist(),
              'side_delta_px':side_delta.tolist(), 'side_source_contours_px':cur['side'].tolist(),
              'limits':{'width_scale':[.80,1.45],'sagittal_delta_px':[-20,20],
                        'smoothing_sigma_px':2.5},
              'interpretation':'Cross-section sculpt guidance only. Pixel distances are converted into actual rest-mesh displacements; same mesh for all views. Neck and crown transitions fade. Not certified anatomical measurement.'}
    OUT.write_text(json.dumps(report,indent=2))
    print(OUT)


if __name__ == '__main__': main()
