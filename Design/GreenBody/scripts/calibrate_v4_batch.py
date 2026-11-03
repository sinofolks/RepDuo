"""Run bounded 3D experiments and retain all evidence; never auto-promote.

Each candidate is a real Blender model, captured by the UNCHANGED collector
and scored by the UNCHANGED calibration implementation. No score is a quality
approval. A fresh output directory is required; no hidden retries or resumes.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
BLENDER='/Applications/Blender.app/Contents/MacOS/Blender'


def experiment(spec,out,builder='build_green_body_v4.py'):
    name=spec['name']
    if not name.replace('-','').replace('_','').isalnum():
        raise ValueError('Experiment names must be file-safe')
    directory=out/name
    directory.mkdir()
    model=directory/'candidate.blend'
    capture=directory/'capture'
    commands=[
        [BLENDER,'--background','--factory-startup','--python-exit-code','1','--python',str(ROOT/'scripts'/builder),'--','--out',str(model),'--params-json',json.dumps(spec['parameters'])],
        [BLENDER,'--background','--factory-startup','--python-exit-code','1','--python',str(ROOT/'calibration/render_candidate.py'),'--','--blend',str(model),'--out',str(capture)],
        [sys.executable,str(ROOT/'calibration/calibrate.py'),'evaluate','--capture',str(capture),'--label',name,'--out',str(directory/'scores')],
    ]
    for step,command in enumerate(commands):
        with (directory/f'step-{step}.log').open('w') as log:
            completed=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
        if completed.returncode:
            result={'name':name,'parameters':spec['parameters'],'status':'failed','step':step,'log':str(directory/f'step-{step}.log')}
            (directory/'experiment.json').write_text(json.dumps(result,indent=2))
            return result
    result_file=next((directory/'scores').glob('*/result.json'))
    score=json.loads(result_file.read_text())
    result={'name':name,'parameters':spec['parameters'],'status':'measured','score':score['composite_score'],
            'protocol':score['protocol_id'],'model':str(model),'result':str(result_file),
            'approval':'not approved; inspect multiview and deformations first'}
    (directory/'experiment.json').write_text(json.dumps(result,indent=2))
    return result


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--spec',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--workers',type=int,default=2,choices=(1,2))
    parser.add_argument('--builder',default='build_green_body_v4.py',
                        choices=('build_green_body_v4.py','build_green_body_v5.py'))
    args=parser.parse_args()
    out=args.out.resolve()
    out.mkdir(parents=True,exist_ok=False)
    specs=json.loads(args.spec.read_text())
    assert len({s['name'] for s in specs})==len(specs)
    results=[]
    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        pending=[executor.submit(experiment,s,out,args.builder) for s in specs]
        for future in as_completed(pending):
            result=future.result()
            results.append(result)
            print(json.dumps(result),flush=True)
    (out/'summary.json').write_text(json.dumps(results,indent=2))


if __name__=='__main__':
    main()
