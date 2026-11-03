"""Create a distinct pose-only protocol; old studio, references and scores stay fixed."""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parent
MODEL_ROOT=ROOT.parent
OUT=ROOT/'multiview-pose-v2'


def main():
    directory=OUT/'profiles'
    directory.mkdir(parents=True,exist_ok=False)
    for view in ('front','side','back'):
        profile=json.loads((ROOT/'multiview/profiles'/f'{view}.json').read_text())
        profile['name']=f'Approved turnaround pose v2 — {view} — same native-material fixed studio'
        del profile['code_dependencies']['scripts/prepare_turnaround_pose.py']
        key='scripts/prepare_turnaround_pose_v2.py'
        profile['code_dependencies'][key]=hashlib.sha256((MODEL_ROOT/key).read_bytes()).hexdigest()
        profile['turnaround_pose_rule']='prepare_turnaround_pose_v2.py; fixed reference-led rules for all models; never mix with pose v1 scores'
        (directory/f'{view}.json').write_text(json.dumps(profile,indent=2))
    (OUT/'runs').mkdir()
    print(OUT)


if __name__=='__main__': main()
