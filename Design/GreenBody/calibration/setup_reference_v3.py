"""Lock authorized harmonization separately; re-score unchanged V10 captures.

Scores belong to a NEW reference protocol. Differences from the old reference
are not model improvement. Old images, protocols, captures and runs are read-only.
"""
import copy
import json
from pathlib import Path
import subprocess
import sys
from calibrate import digest, init_reference, evaluate_capture
from multiview_run import aggregate_results, VIEWS

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'multiview-reference-v3'


def main():
    source=ROOT.parent/'reference/green-body-turnaround-v3b-harmonized.png'
    audit=json.loads(source.with_suffix('.json').read_text())
    assert audit['candidate_sha256']==digest(source)
    assert audit['source_pixel_front_back_mirror_iou']==1
    assert audit['front_back_mirror_iou']==1
    assert audit['front_and_side_pixels_unchanged']
    assert audit['source_unchanged']
    OUT.mkdir(exist_ok=False)
    for directory in ('configs','profiles','runs'):
        (OUT/directory).mkdir()
    front=json.loads((ROOT/'multiview/configs/front.json').read_text())
    results={}
    original_capture_root=ROOT/'multiview-pose-v2/captures/V10-legdepth'
    for view in VIEWS:
        cfg=json.loads((ROOT/'multiview/configs'/f'{view}.json').read_text())
        cfg.update({'revision':3,'image':'../../../reference/'+source.name,
                    'image_sha256':digest(source),'reference_series':'turnaround-v3-harmonized'})
        cfg['harmonization']={'method':audit['method'], 'audit_sha256':digest(source.with_suffix('.json')),
            'original_reference_sha256':audit['original_sha256'],
            'authorization':'User confirmed reference correction, then explicitly permitted programmatic editing: 允许啊，快点吧',
            'scope':'Original front and side pixels unchanged; original back texture transported inside mirrored-front silhouette.',
            'not_a_model_render':True,'final_visual_user_approval':False}
        cfg['annotation_note']+=' 新版为用户授权的轮廓校正，不是实测三维；背面关节由正面镜像推定。新旧参考评分不得当作模型进步相减。'
        if view=='back':
            cfg['landmarks']={}
            for name,item in front['landmarks'].items():
                other=name.replace('screen_left','screen_right') if 'screen_left' in name else name.replace('screen_right','screen_left')
                point=copy.deepcopy(item)
                point['xy']=[audit['back_reflection_x_sum']-item['xy'][0],item['xy'][1]]
                point['source']='Inferred mirror of authoritative front annotation; not independently observed'
                cfg['landmarks'][other]=point
        path=OUT/'configs'/f'{view}.json'
        path.write_text(json.dumps(cfg,indent=2,ensure_ascii=False))
        (OUT/'profiles'/f'{view}.json').write_bytes((ROOT/'multiview-pose-v2/profiles'/f'{view}.json').read_bytes())
        init_reference(path,OUT/'references'/view)
        results[view]=evaluate_capture(OUT/'references'/view,original_capture_root/view,
                                      'V10-baseline-ref3-'+view,OUT/'runs')
    summary=aggregate_results(results)
    summary.update({'reference_version':'v3-harmonized','pose_version':'v2',
        'baseline_model':'V10-legdepth', 'capture_mode':'Re-evaluation of unchanged, hash-verified V10 captures; no new rendering',
        'capture_root':str(original_capture_root), 'reference':str(source),
        'model_improvement_claimed':False,
        'old_reference_scores_comparable':False,
        'view_results':{v:str(OUT/'runs'/results[v]['run_id']/'result.json') for v in VIEWS}})
    (OUT/'baseline-summary.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False))
    subprocess.run([sys.executable,str(ROOT/'calibrate.py'),'report','--runs',str(OUT/'runs'),
                    '--out',str(OUT/'report.html')],check=True)
    print(json.dumps({'scores':summary['scores'],'mean':summary['equal_view_mean'],
                      'minimum':summary['minimum_view_score'],'report':str(OUT/'report.html')},indent=2))


if __name__=='__main__':main()
