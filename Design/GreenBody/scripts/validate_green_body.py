"""Read-only Blender checks for GreenBody-v1.blend.

Example:
  blender --background GreenBody-v1.blend --python validate_green_body.py

Only validation.json is written, next to this script's parent directory. The
loaded scene, original meshes, materials, weights, and .blend file are not
changed. Evaluated temporary meshes and inspection-only BMeshes are released.
"""

from collections import Counter
from datetime import datetime, timezone
import hashlib
import itertools
import json
import math
from pathlib import Path

import bmesh
import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "validation.json"
WEIGHT_TOLERANCE = 1e-4
AREA_EPSILON = 1e-12
SAMPLE_LIMIT = 24


def _finite(values):
    return all(math.isfinite(float(value)) for value in values)


def _issue(report, severity, check, message):
    report[severity].append({"check": check, "message": message})


def _fingerprint(path):
    if not path or not path.is_file():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    stat = path.stat()
    return {"path": str(path), "size_bytes": stat.st_size,
            "mtime_ns": stat.st_mtime_ns, "sha256": digest.hexdigest()}


def _bounds(points):
    valid = [tuple(point) for point in points if _finite(point)]
    if not valid:
        return None
    low = tuple(min(point[axis] for point in valid) for axis in range(3))
    high = tuple(max(point[axis] for point in valid) for axis in range(3))
    return {"minimum": low, "maximum": high,
            "dimensions": tuple(high[axis] - low[axis] for axis in range(3))}


def _connected_components(mesh):
    parents = list(range(len(mesh.vertices)))
    sizes = [1] * len(parents)

    def find(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    for edge in mesh.edges:
        a, b = (find(index) for index in edge.vertices)
        if a != b:
            if sizes[a] < sizes[b]:
                a, b = b, a
            parents[b] = a
            sizes[a] += sizes[b]
    components = Counter(find(index) for index in range(len(parents)))
    return sorted(components.values(), reverse=True)


def check_original_mesh(body, report):
    mesh = body.data
    nonfinite = [vertex.index for vertex in mesh.vertices if not _finite(vertex.co)]
    zero_area = [face.index for face in mesh.polygons
                 if math.isfinite(face.area) and face.area <= AREA_EPSILON]
    nonfinite_area = [face.index for face in mesh.polygons
                      if not math.isfinite(face.area)]
    repeated_indices = [face.index for face in mesh.polygons
                        if len(set(face.vertices)) != len(face.vertices)]
    components = _connected_components(mesh)
    inspection = bmesh.new()
    try:
        inspection.from_mesh(mesh)
        inspection.edges.ensure_lookup_table()
        nonmanifold = [edge.index for edge in inspection.edges if not edge.is_manifold]
        boundary = [edge.index for edge in inspection.edges if edge.is_boundary]
        wire = [edge.index for edge in inspection.edges if edge.is_wire]
        overconnected = [edge.index for edge in inspection.edges if len(edge.link_faces) > 2]
        loose_vertices = [vertex.index for vertex in inspection.verts if not vertex.link_edges]
    finally:
        inspection.free()
    report["original_mesh"] = {
        "object": body.name, "mesh": mesh.name,
        "vertex_count": len(mesh.vertices), "edge_count": len(mesh.edges),
        "face_count": len(mesh.polygons),
        "polygon_size_histogram": dict(Counter(len(face.vertices) for face in mesh.polygons)),
        "all_vertex_coordinates_finite": not nonfinite,
        "nonfinite_vertex_indices_sample": nonfinite[:SAMPLE_LIMIT],
        "zero_area_threshold_square_meters_local": AREA_EPSILON,
        "zero_area_face_count": len(zero_area),
        "zero_area_face_indices_sample": zero_area[:SAMPLE_LIMIT],
        "nonfinite_face_area_count": len(nonfinite_area),
        "repeated_index_face_count": len(repeated_indices),
        "nonmanifold_edge_count_including_boundary_and_wire": len(nonmanifold),
        "boundary_edge_count": len(boundary), "wire_edge_count": len(wire),
        "overconnected_edge_count": len(overconnected),
        "nonmanifold_edge_indices_sample": nonmanifold[:SAMPLE_LIMIT],
        "loose_vertex_count": len(loose_vertices),
        "loose_vertex_indices_sample": loose_vertices[:SAMPLE_LIMIT],
        "connected_component_count": len(components),
        "connected_component_vertex_counts": components,
        "bounds_local_meters": _bounds(vertex.co for vertex in mesh.vertices),
    }
    if not mesh.vertices or not mesh.polygons:
        _issue(report, "errors", "original_mesh", "The body mesh has no vertices or faces.")
    if nonfinite or nonfinite_area:
        _issue(report, "errors", "original_mesh", "Non-finite coordinates or face areas found.")
    if zero_area or repeated_indices:
        _issue(report, "errors", "original_mesh", "Degenerate or repeated-index faces found.")
    if nonmanifold:
        _issue(report, "warnings", "topology",
               f"{len(nonmanifold)} non-manifold edges, including {len(boundary)} boundary "
               f"and {len(wire)} wire edges. Inspect openings before animation approval.")
    if len(components) != 1 or loose_vertices:
        _issue(report, "warnings", "topology",
               f"{len(components)} connected components and {len(loose_vertices)} loose vertices.")


def check_armature_weights(body, report):
    scene_rigs = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    modifiers = [modifier for modifier in body.modifiers if modifier.type == "ARMATURE"]
    rigs = [modifier.object for modifier in modifiers
            if modifier.object is not None and modifier.object.type == "ARMATURE"]
    bone_names = {bone.name for rig in rigs for bone in rig.data.bones if bone.use_deform}
    group_names = {group.index: group.name for group in body.vertex_groups}
    bone_groups = {index for index, name in group_names.items() if name in bone_names}
    ignored_groups = [name for index, name in group_names.items() if index not in bone_groups]
    totals, outside_tolerance, unweighted, invalid = [], [], [], []
    for vertex in body.data.vertices:
        weights = [assignment.weight for assignment in vertex.groups
                   if assignment.group in bone_groups]
        if not _finite(weights) or any(weight < 0 or weight > 1 + WEIGHT_TOLERANCE
                                       for weight in weights):
            invalid.append(vertex.index)
        total = sum(weights)
        if math.isfinite(total):
            totals.append(total)
            if total <= WEIGHT_TOLERANCE:
                unweighted.append(vertex.index)
            if abs(total - 1.0) > WEIGHT_TOLERANCE:
                outside_tolerance.append({"vertex": vertex.index, "sum": total})
        else:
            outside_tolerance.append({"vertex": vertex.index, "sum": "non-finite"})
    report["armature_weights"] = {
        "scene_armatures": [rig.name for rig in scene_rigs],
        "associated_armatures": list(dict.fromkeys(rig.name for rig in rigs)),
        "armature_modifiers": [{"name": modifier.name,
                                "target": modifier.object.name if modifier.object else None,
                                "show_viewport": modifier.show_viewport,
                                "show_render": modifier.show_render} for modifier in modifiers],
        "deforming_bone_name_count": len(bone_names),
        "matched_bone_vertex_group_count": len(bone_groups),
        "ignored_nonbone_vertex_groups": ignored_groups,
        "normalization_tolerance": WEIGHT_TOLERANCE,
        "bone_weight_sum_minimum": min(totals) if totals else None,
        "bone_weight_sum_maximum": max(totals) if totals else None,
        "maximum_absolute_normalization_error": max((abs(value - 1) for value in totals), default=None),
        "outside_tolerance_count": len(outside_tolerance),
        "outside_tolerance_sample": outside_tolerance[:SAMPLE_LIMIT],
        "unweighted_vertex_count": len(unweighted),
        "unweighted_vertex_indices_sample": unweighted[:SAMPLE_LIMIT],
        "invalid_weight_vertex_count": len(invalid),
        "invalid_weight_vertex_indices_sample": invalid[:SAMPLE_LIMIT],
        "all_vertices_normalized": bool(bone_groups) and not outside_tolerance and not invalid,
    }
    if not scene_rigs or not rigs or not bone_names:
        _issue(report, "errors", "armature_weights", "No valid body-linked deforming armature found.")
    if outside_tolerance or invalid:
        _issue(report, "errors", "armature_weights",
               f"{len(outside_tolerance)} vertices have non-unit bone-weight sums; "
               f"{len(invalid)} have invalid bone weights. Non-bone masks are excluded.")


def check_evaluated_mesh_and_cameras(body, report):
    scene = bpy.context.scene
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated_body = body.evaluated_get(depsgraph)
    evaluated_mesh = evaluated_body.to_mesh(preserve_all_data_layers=False, depsgraph=depsgraph)
    try:
        world_points = [evaluated_body.matrix_world @ vertex.co for vertex in evaluated_mesh.vertices]
        nonfinite = [index for index, point in enumerate(world_points) if not _finite(point)]
        bounds = _bounds(world_points)
        report["evaluated_mesh"] = {
            "evaluation_context": "Current frame and viewport dependency graph; no scene mutation",
            "vertex_count": len(evaluated_mesh.vertices),
            "face_count": len(evaluated_mesh.polygons),
            "all_world_coordinates_finite": not nonfinite,
            "nonfinite_vertex_indices_sample": nonfinite[:SAMPLE_LIMIT],
            "bounds_world_meters": bounds,
            "modifiers": [{"name": modifier.name, "type": modifier.type,
                           "show_viewport": modifier.show_viewport, "show_render": modifier.show_render,
                           **({"viewport_levels": modifier.levels, "render_levels": modifier.render_levels}
                              if modifier.type == "SUBSURF" else {})} for modifier in body.modifiers],
        }
        if nonfinite or bounds is None:
            _issue(report, "errors", "evaluated_mesh", "Evaluated mesh is empty or has non-finite coordinates.")
            return
        if any(dimension <= 0 for dimension in bounds["dimensions"]):
            _issue(report, "errors", "evaluated_mesh", "Evaluated bounding box has a zero-size dimension.")
        for modifier in body.modifiers:
            if modifier.show_viewport != modifier.show_render or (
                    modifier.type == "SUBSURF" and modifier.levels != modifier.render_levels):
                _issue(report, "warnings", "evaluated_mesh",
                       f"Modifier {modifier.name} differs between viewport and render; framing is viewport-evaluated.")
        corners = [Vector(corner) for corner in itertools.product(
            *[(bounds["minimum"][axis], bounds["maximum"][axis]) for axis in range(3)])]
        report["camera_framing"] = []
        cameras = [obj for obj in scene.objects if obj.type == "CAMERA"]
        expected = {"GB_Camera_Hero", "GB_Camera_Front", "GB_Camera_Side", "GB_Camera_Back"}
        missing = sorted(expected.difference(camera.name for camera in cameras))
        if missing:
            _issue(report, "errors", "camera_framing", "Missing required cameras: " + ", ".join(missing))
        for camera in cameras:
            projections = [world_to_camera_view(scene, camera, corner) for corner in corners]
            valid = all(_finite(point) for point in projections)
            contained = valid and all(
                -1e-5 <= point.x <= 1.0 + 1e-5 and -1e-5 <= point.y <= 1.0 + 1e-5
                and camera.data.clip_start <= point.z <= camera.data.clip_end
                for point in projections)
            framing = {"camera": camera.name, "type": camera.data.type,
                       "ortho_scale": camera.data.ortho_scale if camera.data.type == "ORTHO" else None,
                       "resolution": [scene.render.resolution_x, scene.render.resolution_y],
                       "all_evaluated_world_bbox_corners_in_frustum": contained,
                       "projected_bbox_corners_ndc_xyz": [tuple(point) for point in projections]}
            if valid:
                framing["ndc_margin"] = {"left": min(point.x for point in projections),
                                         "right": 1 - max(point.x for point in projections),
                                         "bottom": min(point.y for point in projections),
                                         "top": 1 - max(point.y for point in projections)}
            report["camera_framing"].append(framing)
            if not contained:
                _issue(report, "errors", "camera_framing",
                       f"{camera.name} does not contain every evaluated body bounding-box corner.")
    finally:
        evaluated_body.to_mesh_clear()


def _linear_to_srgb(value):
    value = max(0.0, min(1.0, float(value)))
    return value * 12.92 if value <= 0.0031308 else 1.055 * value ** (1.0 / 2.4) - 0.055


def check_materials_and_images(body, report):
    report["body_materials"] = []
    for material in body.data.materials:
        if material is None:
            report["body_materials"].append({"name": None})
            continue
        shaders = []
        for node in material.node_tree.nodes if material.use_nodes and material.node_tree else []:
            if node.type != "BSDF_PRINCIPLED":
                continue
            base = tuple(node.inputs["Base Color"].default_value)
            shaders.append({"node": node.name, "base_color_linear_rgba": base,
                            "base_color_srgb_hex": "#" + "".join(
                                f"{round(_linear_to_srgb(value) * 255):02X}" for value in base[:3]),
                            "base_color_is_linked": node.inputs["Base Color"].is_linked,
                            "roughness": node.inputs["Roughness"].default_value,
                            "metallic": node.inputs["Metallic"].default_value})
        report["body_materials"].append({"name": material.name, "principled_shaders": shaders})
    report["external_images"] = []
    for image in bpy.data.images:
        if image.source not in {"FILE", "MOVIE", "SEQUENCE", "TILED"}:
            continue
        packed = bool(image.packed_file) or bool(getattr(image, "packed_files", []))
        entry = {"name": image.name, "source": image.source,
                 "filepath": image.filepath, "packed": packed, "missing_paths": []}
        if not packed:
            resolved = bpy.path.abspath(image.filepath, library=image.library)
            candidates = [resolved] if image.filepath else []
            if image.source == "TILED" and ("<UDIM>" in resolved or "<UVTILE>" in resolved):
                candidates = []
                for tile in image.tiles:
                    offset = tile.number - 1001
                    tile_path = resolved.replace("<UDIM>", str(tile.number)).replace(
                        "<UVTILE>", f"u{offset % 10 + 1}_v{offset // 10 + 1}")
                    candidates.append(tile_path)
            entry["resolved_paths"] = candidates
            entry["missing_paths"] = [path for path in candidates if not Path(path).is_file()]
            if not candidates:
                entry["missing_paths"].append("<empty filepath or tile set>")
            if entry["missing_paths"]:
                _issue(report, "errors", "external_images", f"Missing external image data for {image.name}.")
        report["external_images"].append(entry)


def _json_safe(value):
    if isinstance(value, float) and not math.isfinite(value):
        return str(value)
    if isinstance(value, dict):
        return {key: _json_safe(item) for key, item in value.items()}
    if isinstance(value, (tuple, list)):
        return [_json_safe(item) for item in value]
    return value


def main():
    blend_path = Path(bpy.data.filepath).resolve() if bpy.data.filepath else None
    before = _fingerprint(blend_path)
    report = {"generated_at_utc": datetime.now(timezone.utc).isoformat(),
              "blender_version": bpy.app.version_string, "blend_file": str(blend_path),
              "read_only_model_validation": True, "errors": [], "warnings": []}
    body = bpy.data.objects.get("GreenBody")
    if body is None or body.type != "MESH":
        _issue(report, "errors", "body", "Expected mesh object GreenBody was not found.")
    else:
        for check in (check_original_mesh, check_armature_weights,
                      check_evaluated_mesh_and_cameras, check_materials_and_images):
            try:
                check(body, report)
            except Exception as error:
                _issue(report, "errors", check.__name__, f"{type(error).__name__}: {error}")
    after = _fingerprint(blend_path)
    report["blend_file_integrity"] = {"before": before, "after": after,
                                      "unchanged": before is not None and before == after}
    if not report["blend_file_integrity"]["unchanged"]:
        _issue(report, "errors", "blend_file_integrity", ".blend fingerprint unavailable or changed.")
    report["status"] = "FAIL" if report["errors"] else (
        "PASS_WITH_WARNINGS" if report["warnings"] else "PASS")
    OUTPUT.write_text(json.dumps(_json_safe(report), indent=2, ensure_ascii=False, allow_nan=False) + "\n")
    print("GREEN_BODY_VALIDATION", json.dumps({"status": report["status"],
          "errors": len(report["errors"]), "warnings": len(report["warnings"]),
          "report": str(OUTPUT)}), flush=True)
    return report


if __name__ == "__main__":
    main()
