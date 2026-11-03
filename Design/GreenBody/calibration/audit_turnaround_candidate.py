"""Audit generated turnaround candidates without editing images or locking references."""
import argparse
import json
from pathlib import Path
import numpy as np
from PIL import Image
from calibrate import digest, largest_component, normalize
from audit_reference_consistency import iou, shifted, score_ceiling

ROOT = Path(__file__).resolve().parent


def masks(path):
    rgb = np.asarray(Image.open(path).convert('RGB'))
    h, w = rgb.shape[:2]
    r, g, b = [rgb[..., i].astype(float) for i in range(3)]
    result = {}
    for view in ('front', 'side', 'back'):
        cfg = json.loads((ROOT / 'multiview/configs' / (view+'.json')).read_text())
        seg = cfg['segmentation']
        mask = (g >= seg['min_green']) & (g > r*seg['green_red_ratio']) & (g > b*seg['green_blue_ratio'])
        roi = cfg['roi']
        x0, y0, x1, y1 = [round(v*s) for v,s in zip(roi, (w/1672,h/941,w/1672,h/941))]
        region = np.zeros(mask.shape, dtype=bool)
        region[y0:y1,x0:x1] = True
        mask = largest_component(mask & region)
        _, normalized, _, alignment = normalize(rgb, mask, {}, cfg['canonical'])
        result[view] = (normalized, alignment)
    return result


def audit(path):
    original = ROOT.parent/'reference/green-body-turnaround-v1-candidate.png'
    old, new = masks(original), masks(path)
    front, back = new['front'][0], np.fliplr(new['back'][0])
    raw = iou(front, back)
    best, dx, dy = max((iou(front, shifted(back, dx, dy)), dx, dy)
                      for dx in range(-12,13) for dy in range(-6,7))
    return {
        'schema': 'greenbody-turnaround-candidate-audit-v1',
        'candidate': str(path.resolve()), 'candidate_sha256': digest(path),
        'original': str(original), 'original_sha256': digest(original),
        'front_back_mirror_iou': raw,
        'translation_sensitivity': {'best_iou':best,'dx':dx,'dy':dy,'applied':False},
        'front_back_ideal_score_ceiling': score_ceiling(best),
        'design_silhouette_retention': {v:iou(old[v][0],new[v][0]) for v in old},
        'alignment': {v:new[v][1] for v in new},
        'reference_selected': False,
        'notes': ['Analysis only; no image is rewritten, warped or locked.',
                  'Mirror IoU is a necessary projection consistency check, not full 3D certification.',
                  'A ceiling above99 does not imply achievable99: other scores may conflict too.',
                  'Design retention measures silhouettes only; visual inspection remains required.']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--image',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True)
    args = parser.parse_args()
    report = audit(args.image)
    with args.out.open('x') as f:
        json.dump(report,f,indent=2)
    print(json.dumps({k:v for k,v in report.items() if k not in ('alignment','notes')},indent=2))
