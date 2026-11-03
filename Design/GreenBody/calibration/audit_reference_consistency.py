"""Read-only front/back feasibility audit for the locked orthographic protocol.

Any one opaque mesh in one pose has mirrored front/back silhouettes. The
Jaccard distance triangle inequality bounds simultaneous reference agreement.
No reference, score formula, camera, or candidate image is modified.
"""
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parent


def iou(a,b):
    return float(np.logical_and(a,b).sum()/np.logical_or(a,b).sum())


def score_ceiling(reference_iou, candidate_mirror_distance=0, iou_weight=30):
    # d(Rf,Rb) <= d(Rf,Cf)+d(Cf,Cb)+d(Cb,Rb).
    return min(100,100-iou_weight*.5*(1-reference_iou-candidate_mirror_distance))


def shifted(mask,dx,dy):
    result=np.zeros_like(mask)
    h,w=mask.shape
    x0,x1=max(0,dx),min(w,w+dx)
    y0,y1=max(0,dy),min(h,h+dy)
    result[y0:y1,x0:x1]=mask[y0-dy:y1-dy,x0-dx:x1-dx]
    return result


def load(path): return np.array(Image.open(path).convert('L'))>127


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    out=ROOT/'reference-consistency-audit.json'
    if out.exists(): raise ValueError('Refusing to overwrite audit')
    front=ROOT/'multiview/references/front/reference_mask.png'
    back=ROOT/'multiview/references/back/reference_mask.png'
    a,b=load(front),np.fliplr(load(back))
    scores=[(iou(a,shifted(b,dx,dy)),dx,dy) for dx in range(-12,13) for dy in range(-6,7)]
    best,dx,dy=max(scores)
    candidate_runs=ROOT/'multiview-pose-v2/runs'
    cf=next(candidate_runs.glob('*-V9-restrained-front'))/'candidate_mask.png'
    cb=next(candidate_runs.glob('*-V9-restrained-back'))/'candidate_mask.png'
    candidate_gap=1-iou(load(cf),np.fliplr(load(cb)))
    capture_paths=[ROOT/'multiview-pose-v2/captures/V9-restrained'/v/'capture.json' for v in ('front','back')]
    captures=[json.loads(p.read_text()) for p in capture_paths]
    assert captures[0]['geometry_hash']==captures[1]['geometry_hash']
    assert captures[0]['pose_hash']==captures[1]['pose_hash']
    for cap in captures: assert cap['effective_profile']['camera']['type']=='ORTHO'
    for name in ('front','back'):
        path=next(candidate_runs.glob('*-V9-restrained-'+name))/'result.json'
        result=json.loads(path.read_text())
        assert result['metrics']['silhouette_iou']['weight']==30
        assert sum(v['weight'] for v in result['metrics'].values())==100
    report={'schema':'greenbody-reference-feasibility-audit-v1',
            'source_hashes':{str(p):digest(p) for p in (front,back,cf,cb)},
            'reference_front_back_mirror_iou':iou(a,b),
            'generous_translation_search':{'range_x_px':[-12,12],'range_y_px':[-6,6],
                'best_iou':best,'best_dx':dx,'best_dy':dy,
                'note':'Read-only sensitivity allowance, not applied to reference or scorer'},
            'observed_v9_candidate_mirror_jaccard_distance':candidate_gap,
            'ideal_mirrored_shape_composite_mean_upper_bound':score_ceiling(best),
            'bound_using_observed_v9_raster_gap':score_ceiling(best,candidate_gap),
            'sensitivity_bound_allowing_one_percent_candidate_raster_gap':score_ceiling(best,.01),
            'derivation':{'assumption':'One opaque mesh, one pose, front/back orthographic cameras; mirrored ideal silhouettes coincide',
                'jaccard_triangle':'IoU(Rf,Cf)+IoU(Rb,Cb) <= 1+IoU(Rf,mirror(Rb))+d(Cf,mirror(Cb))',
                'all_other_scores_assumed':100,'silhouette_weight':30,
                'composite_mean_bound':'100 - 15 * (1 - reference_IoU - candidate_mirror_distance)',
                'consequence':'If the mean front/back upper bound is below99, both views cannot simultaneously reach99 under these assumptions'},
            'limitations':['The1% raster-gap case is a sensitivity allowance, not a universal renderer error guarantee',
                'This bounds the locked image-agreement protocol, not subjective quality or actual 3D reconstruction percentage',
                'No claim that the current model is close to this upper bound',
                'Harmonizing the approved reference, changing pose assumptions or redefining the99 target requires explicit user direction; no such change performed'],
            'recommended_next_decision':'Ask whether to harmonize a geometrically consistent reference turnaround while retaining the approved design. Do not inflate scores or silently alter the reference.'}
    out.write_text(json.dumps(report,indent=2))
    print(json.dumps({k:v for k,v in report.items() if k not in ('source_hashes','derivation','limitations')},indent=2))


if __name__=='__main__': main()
