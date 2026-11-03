"""Local head tessellation and oval ear relief, preserving original rig data.

Experimental geometry only. No reference, scoring, camera or pose mutations.
New points receive explicit barycentric skin/key interpolation from the source.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_green_body import smoothstep
from validate_green_body import check_original_mesh, check_armature_weights


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def barycentric(p, a, b, c):
    u, v, w = b-a, c-a, p-a
    aa, ab, bb = u.dot(u), u.dot(v), v.dot(v)
    den = aa*bb-ab*ab
    assert den > 1e-18
    t = (bb*w.dot(u)-ab*w.dot(v))/den
    s = (aa*w.dot(v)-ab*w.dot(u))/den
    values = np.maximum(0, [1-t-s, t, s])
    return values / values.sum()


def features(y, z):
    u, v = (y+.011)/.03, (z-1.686)/.04
    return [1, u, v, u*u, u*v, v*v]


def main():
    assert bpy.app.background
    p = argparse.ArgumentParser()
    p.add_argument('--source', type=Path, default=ROOT/'GreenBody-v23-work.blend')
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--cuts', type=int, default=2)
    p.add_argument('--ear', action='store_true')
    p.add_argument('--surface-project', action='store_true')
    p.add_argument('--open-rim', action='store_true')
    args = p.parse_args(sys.argv[sys.argv.index('--')+1:])
    assert 1 <= args.cuts <= 3
    source, out = args.source.resolve(), args.out.resolve()
    assert not out.exists() and not out.with_suffix('.json').exists()
    before = digest(source)
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    body = bpy.data.objects['GreenBody']
    mesh = body.data
    original = [v.co.copy() for v in mesh.vertices]
    shape = {k.name: [v.co.copy() for v in k.data] for k in mesh.shape_keys.key_blocks}
    weights = [dict((g.group,g.weight) for g in v.groups) for v in mesh.vertices]
    driver_ids = [c.as_pointer() for c in mesh.shape_keys.animation_data.drivers]
    smooth_tree = None
    if args.surface_project:
        modifier_flags = [(m,m.show_viewport) for m in body.modifiers]
        driver_flags = [(c,c.mute) for c in mesh.shape_keys.animation_data.drivers]
        key_values = [(k,k.value) for k in mesh.shape_keys.key_blocks]
        for c,flag in driver_flags: c.mute = True
        for k,value in key_values: k.value = 0
        for m,flag in modifier_flags:
            if m.type!='SUBSURF': m.show_viewport = False
        bpy.context.view_layer.update()
        ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
        em = ev.to_mesh()
        em.calc_loop_triangles()
        smooth_tree = BVHTree.FromPolygons([v.co.copy() for v in em.vertices],
                                         [tuple(t.vertices) for t in em.loop_triangles],all_triangles=True)
        ev.to_mesh_clear()
        for k,value in key_values: k.value = value
        for c,flag in driver_flags: c.mute = flag
        for m,flag in modifier_flags: m.show_viewport = flag
        bpy.context.view_layer.update()
    mesh.calc_loop_triangles()
    triangles = [tuple(t.vertices) for t in mesh.loop_triangles]
    tree = BVHTree.FromPolygons(original, triangles, all_triangles=True)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    old_vertices = list(bm.verts)
    assert all(v.index==i for i,v in enumerate(old_vertices))
    print('BM_PRE_COORD_ERROR',max((v.co-original[i]).length for i,v in enumerate(old_vertices)),flush=True)
    layers = {name:bm.verts.layers.shape[name] for name in shape}
    deform = bm.verts.layers.deform.active
    assert deform is not None
    def domain(v):
        return 1.625 < v.co.z < 1.75 and abs(v.co.x-.015) > .035
    edges = [e for e in bm.edges if all(domain(v) for v in e.verts)]
    assert len(edges) > 100
    bmesh.ops.subdivide_edges(bm, edges=edges, cuts=args.cuts, smooth=0,
                             use_grid_fill=True)
    # Retained control points are not silently resampled or rebound.
    # The operation may invalidate Python BMesh vertex wrappers. Re-establish
    # exact geometric correspondence, requiring unique retained coordinates.
    bm.verts.ensure_lookup_table()
    kd = KDTree(len(bm.verts))
    for i,v in enumerate(bm.verts):
        kd.insert(v.co,i)
    kd.balance()
    matches = [kd.find(co) for co in original]
    assert len({i for co,i,d in matches})==len(original)
    old_vertices = [bm.verts[i] for co,i,d in matches]
    source_index = {v:i for i,v in enumerate(old_vertices)}
    coord_error = max(d for co,i,d in matches)
    assert coord_error<1e-7, ('Retained coordinate error',coord_error)
    for name,layer in layers.items():
        assert all((v[layer]-shape[name][i]).length < 1e-7 for i,v in enumerate(old_vertices))
    max_distance = 0.
    new_count = 0
    for v in bm.verts:
        if v in source_index:
            continue
        new_count += 1
        near,normal,tid,distance = tree.find_nearest(v.co)
        assert tid is not None
        max_distance = max(max_distance,distance)
        ids = triangles[tid]
        mix = barycentric(near,*(original[i] for i in ids))
        v[deform].clear()
        for group in set().union(*(weights[i] for i in ids)):
            weight = sum(float(t)*weights[i].get(group,0) for i,t in zip(ids,mix))
            if weight > 0:
                v[deform][group] = weight
        for name,layer in layers.items():
            delta = sum(((shape[name][i]-shape['Basis'][i])*float(t)
                         for i,t in zip(ids,mix)),Vector())
            v[layer] = v.co+delta
    assert new_count > 100 and max_distance < .001, max_distance
    # Fit a smooth local skull surface from source points outside the old ear.
    fits = {}
    for side in (-1,1):
        rows, values = [],[]
        for co in original:
            x,y,z = co
            r = math.hypot((y+.011)/.019,(z-1.686)/.028)
            if side*(x-.015)>.05 and 1.30<r<2.20 and abs(y+.011)<.055 and 1.63<z<1.744:
                rows.append(features(y,z)); values.append(side*(x-.015))
        assert len(rows)>20
        coefficient,*_ = np.linalg.lstsq(rows,values,rcond=None)
        fits[side] = coefficient
    edited = 0
    max_sculpt = 0.
    max_projection = 0.
    relative_error = 0.
    for v in bm.verts:
        before_delta = {name:v[layer]-v[layers['Basis']] for name,layer in layers.items()}
        if smooth_tree is not None:
            x,y,z = v.co
            projection_mask = (smoothstep(1.625,1.650,z)*(1-smoothstep(1.725,1.750,z))
                               *smoothstep(.035,.052,abs(x-.015)))
            if projection_mask > 0:
                hit,normal,index,distance = smooth_tree.find_nearest(v.co)
                assert index is not None and distance < .010
                d = (hit-v.co)*projection_mask
                v.co += d
                for layer in layers.values(): v[layer] += d
                max_projection = max(max_projection,d.length)
        x,y,z = v.co
        side = 1 if x>.015 else -1
        r = math.hypot((y+.011-.11*(z-1.686))/.019,(z-1.686)/.028)
        mask = (1-smoothstep(1.10,1.65,r))*smoothstep(.04,.065,abs(x-.015)) if args.ear else 0.
        if mask>0:
            skull = float(np.dot(fits[side],features(y,z)))
            support = 1-smoothstep(.90,1.15,r)
            relief = support*(.0085+.0040*math.exp(-.5*((r-.73)/.15)**2)
                              -.0040*math.exp(-.5*(r/.42)**2))
            if args.open_rim:
                anterior = (y+.011-.11*(z-1.686))/.019
                helix = .0036*math.exp(-.5*((r-.76)/.12)**2)
                helix *= .30+.70*smoothstep(-.65,.10,anterior)
                bowl = .0048*math.exp(-.5*(r/.42)**2)*smoothstep(1.660,1.681,z)
                tragus = .0018*math.exp(-.5*((anterior+.47)/.18)**2)*math.exp(-.5*((z-1.681)/.007)**2)
                relief = support*(.0075+helix-bowl+tragus)
            target = .015+side*(skull+relief)
            dx = (target-x)*mask
            assert abs(dx)<.025, dx
            d = Vector((dx,0,0))
            v.co += d
            for layer in layers.values():
                v[layer] += d
            edited += 1
            max_sculpt = max(max_sculpt,abs(dx))
        relative_error = max(relative_error,max(((v[layer]-v[layers['Basis']])-before_delta[name]).length
                                                for name,layer in layers.items()))
    assert relative_error < 1e-6
    assert all(e.is_manifold for e in bm.edges)
    bm.verts.index_update()
    old_new_indices = [v.index for v in old_vertices]
    expected_coordinates = {v.index:v.co.copy() for v in bm.verts}
    expected_shapes = {name:{v.index:v[layer].copy() for v in bm.verts}
                       for name,layer in layers.items()}
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update(); bpy.context.view_layer.update()
    assert all(len(k.data)==len(mesh.vertices) for k in mesh.shape_keys.key_blocks)
    stored_error = max((v.co-expected_coordinates[v.index]).length for v in mesh.vertices)
    stored_key_error = max((p.co-expected_shapes[k.name][i]).length
                           for k in mesh.shape_keys.key_blocks for i,p in enumerate(k.data))
    assert stored_error < 1e-7 and stored_key_error < 1e-7, (stored_error,stored_key_error)
    assert driver_ids == [c.as_pointer() for c in mesh.shape_keys.animation_data.drivers]
    assert all(c.driver.is_valid for c in mesh.shape_keys.animation_data.drivers)
    for old_index,new_index in enumerate(old_new_indices):
        assert weights[old_index] == dict((g.group,g.weight) for g in mesh.vertices[new_index].groups)
        if original[old_index].z<=1.625 or original[old_index].z>=1.75:
            assert (mesh.vertices[new_index].co-original[old_index]).length < 1e-7
    report = {'errors':[],'warnings':[], 'source':str(source),'source_sha256':before,
              'cuts':args.cuts,'ear_sculpt':args.ear,'new_vertices':new_count,
              'original_vertex_count':len(original),'retained_vertex_weights_unchanged':True,
              'new_vertex_binding':'closest source triangle barycentric relative keys and skin weights',
              'maximum_new_point_source_surface_distance_m':max_distance,
              'sculpted_vertices':edited,'maximum_sculpt_displacement_m':max_sculpt,
              'relative_key_error_m':relative_error,
              'surface_project':args.surface_project,'maximum_surface_projection_m':max_projection,
              'open_rim':args.open_rim,
              'retained_coordinate_error_before_sculpt_m':coord_error,
              'mesh_storage_error_m':stored_error,'shape_storage_error_m':stored_key_error,
              'limitations':['Local subdivision changes the limit surface; not a shape-identical operation.',
                             'No final animation or fidelity approval.']}
    check_original_mesh(body,report); check_armature_weights(body,report)
    assert not report['errors'],report['errors']
    assert report['original_mesh']['connected_component_count']==1
    out.parent.mkdir(parents=True,exist_ok=True)
    bpy.context.scene['version']='V24 local head tessellation and oval ear study'
    bpy.context.scene['approved_for_animation']=False
    bpy.context.scene.cycles.device='CPU'
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    assert digest(source)==before
    report.update(candidate=str(out),candidate_sha256=digest(out),source_unchanged=True,
                  builder_sha256=digest(__file__))
    out.with_suffix('.json').write_text(json.dumps(report,indent=2))
    print('V24_CANDIDATE',out,flush=True)


if __name__=='__main__':
    main()
