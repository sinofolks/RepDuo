"""Bounded lower-face taper/plane sculpt, preserving rig and corrective deltas."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_green_body import smoothstep
from validate_green_body import check_original_mesh, check_armature_weights


def digest(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def gaussian(value, center, width):
    return math.exp(-.5*((value-center)/width)**2)


def main():
    assert bpy.app.background
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--jaw-taper', type=float, default=.12)
    parser.add_argument('--face-forward', type=float, default=.008)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    assert 0 <= args.jaw_taper <= .2 and 0 <= args.face_forward <= .012
    source, out = args.source.resolve(), args.out.resolve()
    assert not out.exists() and not out.with_suffix('.json').exists()
    source_hash = digest(source)
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    body = bpy.data.objects['GreenBody']
    original = [v.co.copy() for v in body.data.vertices]
    shapes = {k.name: [p.co.copy() for p in k.data] for k in body.data.shape_keys.key_blocks}
    weights = [tuple((g.group, g.weight) for g in v.groups) for v in body.data.vertices]
    delta = []
    for co in original:
        x,y,z = co
        center_x = .015*smoothstep(1.48,1.66,z)
        x -= center_x
        support = smoothstep(1.565,1.59,z)*(1-smoothstep(1.72,1.76,z))
        dx = -x*args.jaw_taper*gaussian(z,1.615,.023)*support
        front = smoothstep(.03,.095,-y)
        dy = -args.face_forward*gaussian(z,1.637,.035)*gaussian(x,0,.045)*front*support
        delta.append(Vector((dx,dy,0)))
    for i,v in enumerate(body.data.vertices):
        v.co = original[i]+delta[i]
    for key in body.data.shape_keys.key_blocks:
        for i,p in enumerate(key.data):
            p.co = shapes[key.name][i]+delta[i]
    body.data.update()
    bpy.context.view_layer.update()
    basis = body.data.shape_keys.key_blocks['Basis']
    error = max(((p.co-basis.data[i].co)-(shapes[k.name][i]-shapes['Basis'][i])).length
                for k in body.data.shape_keys.key_blocks for i,p in enumerate(k.data))
    assert error < 1e-6
    assert weights == [tuple((g.group,g.weight) for g in v.groups) for v in body.data.vertices]
    assert all(d.length==0 for co,d in zip(original,delta) if co.z<=1.565 or co.z>=1.76)
    report = {'errors':[], 'warnings':[], 'jaw_taper':args.jaw_taper,
              'face_forward_m':args.face_forward, 'changed_vertices':sum(d.length>1e-8 for d in delta),
              'maximum_displacement_m':max(d.length for d in delta), 'shape_delta_error_m':error,
              'rig_weights_unchanged':True, 'source':str(source), 'source_sha256':source_hash}
    check_original_mesh(body,report)
    check_armature_weights(body,report)
    assert not report['errors'],report['errors']
    assert report['original_mesh']['connected_component_count']==1
    assert report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire']==0
    assert all(c.driver.is_valid for c in body.data.shape_keys.animation_data.drivers)
    bpy.context.scene['version']='V23 lower-face taper and plane study'
    bpy.context.scene['approved_for_animation']=False
    bpy.context.scene.cycles.device='CPU'
    out.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert digest(source)==source_hash
    report.update(candidate=str(out),candidate_sha256=digest(out),source_unchanged=True,builder_sha256=digest(__file__))
    out.with_suffix('.json').write_text(json.dumps(report,indent=2))
    print('V23_CANDIDATE',out,flush=True)


if __name__=='__main__':
    main()
