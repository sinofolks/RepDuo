"""Bounded multi-view-constrained head/neck sculpt on the actual closed mesh."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from build_green_body import smoothstep
from validate_green_body import check_original_mesh, check_armature_weights


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def interpolate(values, row):
    position = min(len(values)-1,max(0,row-40))
    i = int(position)
    j = min(len(values)-1,i+1)
    t = position-i
    if isinstance(values[i],list):
        return [(1-t)*a+t*b for a,b in zip(values[i],values[j])]
    return (1-t)*values[i]+t*values[j]


def anatomical_sculpt(body, strength, neck_strength, lowered_jaw=False):
    """Smooth localized volumes; never spread nose silhouette over whole head."""
    def g(x, center, width):
        return math.exp(-.5*((x-center)/width)**2)
    count = 0
    for v in body.data.vertices:
        x,y,z = v.co
        if z <= 1.47:
            continue
        fade = smoothstep(1.47,1.51,z)*(1-smoothstep(1.80,1.8198,z))
        face = smoothstep(.065,.105,-y)
        jaw = g(z,1.614,.027)
        # Broader upper cranium, jaw corners and a less attenuated neck.
        v.co.x += x*fade*(strength*(.10*g(z,1.767,.037)+.22*jaw)
                           +neck_strength*.24*g(z,1.544,.033))
        # The chin is a local anterior volume, NOT a horizontal ring extrusion.
        center = g(x,0,.038)
        if lowered_jaw:
            # Extend the lower face vertically, without creating a projecting beak.
            v.co.z -= strength*fade*smoothstep(.025,.080,-y)*.022*g(z,1.617,.030)
        else:
            v.co.y -= strength*fade*face*center*(.025*g(z,1.613,.025)+.006*g(z,1.648,.030))
            v.co.z -= strength*fade*face*g(x,0,.052)*.010*g(z,1.613,.025)
        # Posterior neck thickness stays independent of facial detail.
        v.co.y += neck_strength*.010*g(z,1.55,.045)*smoothstep(-.025,.025,y)*fade
        count += 1
    return count


def main():
    assert bpy.app.background
    parser = argparse.ArgumentParser()
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--strength',type=float,default=1)
    parser.add_argument('--neck-strength',type=float,default=.6)
    parser.add_argument('--method',choices=('sections','anatomical','lowered-jaw'),default='sections')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    if not all(0 <= v <= 1 for v in (args.strength,args.neck_strength)):
        raise ValueError('Strengths must be finite and within [0,1]')
    source,out = ROOT/'GreenBody-v7-work.blend',args.out.resolve()
    if out.exists() or out.with_suffix('.json').exists():
        raise ValueError('Refusing to overwrite candidate/evidence')
    data_path = ROOT/'v8-head-sections.json'
    data = json.loads(data_path.read_text())
    source_hash = digest(source)
    assert source_hash == data['source_model_sha256']
    assert digest(ROOT/'reference/green-body-turnaround-v1-candidate.png') == data['reference_sha256']
    bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False)
    body,rig = bpy.data.objects['GreenBody'],bpy.data.objects['GB_ReviewArmature']
    assert all(abs(body.matrix_world[i][j]-Matrix.Identity(4)[i][j]) < 1e-6 for i in range(4) for j in range(4))
    head = rig.pose.bones['head']
    deform = rig.matrix_world @ head.matrix @ head.bone.matrix_local.inverted()
    assert all(abs(deform[i][j]-Matrix.Identity(4)[i][j]) < 1e-5 for i in range(3) for j in range(3)), 'Expected untranslated-axis canonical head'
    # Below-head blend is safe only if the neck shares the same deformation.
    for name in ('neck01','neck02','neck03'):
        b = rig.pose.bones[name]
        matrix = rig.matrix_world @ b.matrix @ b.bone.matrix_local.inverted()
        assert all(abs(matrix[i][j]-deform[i][j]) < 1e-5 for i in range(4) for j in range(4))
    original = [v.co.copy() for v in body.data.vertices]
    weights = [tuple((g.group,g.weight) for g in v.groups) for v in body.data.vertices]
    alignment = data['side_alignment']
    source_px_per_m = 960/2.1
    px_per_m = source_px_per_m*alignment['scale']
    edited = 0
    for v in body.data.vertices if args.method == 'sections' else []:
        if v.co.z <= 1.47:
            continue
        world = deform @ v.co
        row = (480-(world.z-.91)*source_px_per_m)*alignment['scale']+alignment['translate'][1]
        col = (384+world.y*source_px_per_m)*alignment['scale']+alignment['translate'][0]
        neck_blend = smoothstep(130,155,row)
        strength = args.strength*(1-neck_blend)+args.neck_strength*neck_blend
        strength *= smoothstep(42,50,row)*(1-smoothstep(150,178,row))
        if strength <= 0:
            continue
        scale = interpolate(data['width_scale'],row)
        lo,hi = interpolate(data['side_source_contours_px'],row)
        front,back = interpolate(data['side_delta_px'],row)
        fraction = min(1,max(0,(col-lo)/max(1,hi-lo)))
        v.co.x *= 1+(scale-1)*strength
        v.co.y += (front*(1-fraction)+back*fraction)/px_per_m*strength
        edited += 1
    if args.method in ('anatomical','lowered-jaw'):
        edited = anatomical_sculpt(body,args.strength,args.neck_strength,args.method == 'lowered-jaw')
    body.data.update()
    report = {'errors':[],'warnings':[], 'parameters':vars(args)|{'out':str(out)},
              'changed_vertex_count':edited,
              'maximum_rest_displacement_m':max((v.co-original[v.index]).length for v in body.data.vertices),
              'lower_body_unchanged':all(v.co == original[v.index] for v in body.data.vertices if original[v.index].z <= 1.47),
              'weights_unchanged':weights == [tuple((g.group,g.weight) for g in v.groups) for v in body.data.vertices]}
    assert report['weights_unchanged'] and report['lower_body_unchanged']
    assert report['maximum_rest_displacement_m'] <= .06
    check_original_mesh(body,report)
    check_armature_weights(body,report)
    assert not report['errors'],report['errors']
    assert report['original_mesh']['connected_component_count'] == 1
    assert report['original_mesh']['nonmanifold_edge_count_including_boundary_and_wire'] == 0
    scene = bpy.context.scene
    scene['version'] = 'V8 approved-turnaround head sculpt: '+args.method
    scene['v8_builder_sha256'] = digest(Path(__file__))
    scene['v8_measurement_sha256'] = digest(data_path)
    scene['approved_for_animation'] = False
    scene.cycles.device = 'CPU'
    out.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert digest(source) == source_hash
    report.update({'source':str(source),'source_sha256':source_hash,'source_unchanged':True,
                   'measurement_sha256':digest(data_path),'builder_sha256':digest(Path(__file__)),
                   'candidate':str(out),'candidate_sha256':digest(out)})
    out.with_suffix('.json').write_text(json.dumps(report,indent=2))
    print('V8_CANDIDATE',out,flush=True)


if __name__ == '__main__': main()
