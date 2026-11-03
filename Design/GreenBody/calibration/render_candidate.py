"""Deterministic geometry/pose calibration capture; never saves the source blend.

blender --background --factory-startup --python render_candidate.py -- \
  --blend PATH --out EMPTY_DIR [--profile PATH] [--native-appearance]

Camera overrides: --camera-location X Y Z, --camera-target X Y Z,
--ortho-scale VALUE. The raw profile hash AND effective configuration hash are
recorded, so a camera change cannot masquerade as a fixed-profile capture.
"""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PROFILE = Path(__file__).with_name("capture-profile-v1.json")
sys.dont_write_bytecode = True
LANDMARK_BONES = {
    "shoulder": "upperarm01", "elbow": "lowerarm01", "wrist": "wrist",
    "hip": "upperleg01", "knee": "lowerleg01", "ankle": "foot",
}


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_hash(value):
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    return hashlib.sha256(encoded).hexdigest()


def serial(value):
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, bpy.types.ID):
        return {"id_type": value.bl_rna.identifier, "name": value.name}
    try:
        return [serial(item) for item in value]
    except TypeError:
        return str(value)


def matrix_rows(matrix):
    return [list(row) for row in matrix]


def mesh_hash(mesh, matrix):
    digest = hashlib.sha256()
    digest.update(struct.pack("<QQ", len(mesh.vertices), len(mesh.polygons)))
    for row in matrix:
        digest.update(struct.pack("<4d", *row))
    for vertex in mesh.vertices:
        digest.update(struct.pack("<3d", *vertex.co))
    for face in mesh.polygons:
        digest.update(struct.pack("<I", len(face.vertices)))
        digest.update(struct.pack("<" + "I" * len(face.vertices), *face.vertices))
    return digest.hexdigest()


def geometry_state(body):
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    try:
        bounds = [[min((evaluated.matrix_world @ v.co)[axis] for v in mesh.vertices),
                   max((evaluated.matrix_world @ v.co)[axis] for v in mesh.vertices)] for axis in range(3)]
        evaluated_hash = mesh_hash(mesh, evaluated.matrix_world)
        evaluated_counts = {"vertices": len(mesh.vertices), "faces": len(mesh.polygons)}
    finally:
        evaluated.to_mesh_clear()
    modifiers = []
    for modifier in body.modifiers:
        item = {"name": modifier.name, "type": modifier.type,
                "show_render": modifier.show_render, "show_viewport": modifier.show_viewport}
        for attribute in ("levels", "render_levels", "factor", "iterations", "vertex_group",
                          "use_deform_preserve_volume", "use_pin_boundary"):
            if hasattr(modifier, attribute):
                item[attribute] = serial(getattr(modifier, attribute))
        modifiers.append(item)
    return {"base_mesh_sha256": mesh_hash(body.data, body.matrix_world),
            "evaluated_mesh_sha256": evaluated_hash,
            "base_counts": {"vertices": len(body.data.vertices), "faces": len(body.data.polygons)},
            "evaluated_counts": evaluated_counts, "bounds_world_xyz_minmax": bounds,
            "modifiers": modifiers,
            "evaluation_note": "Evaluated dependency graph at fixed frame; modifier viewport/render differences recorded."}


def pose_state(body):
    rigs = [modifier.object for modifier in body.modifiers
            if modifier.type == "ARMATURE" and modifier.object and modifier.object.type == "ARMATURE"]
    records = []
    for rig in dict.fromkeys(rigs):
        records.append({"object": rig.name, "world_matrix": matrix_rows(rig.matrix_world),
                        "bones": {bone.name: {"matrix": matrix_rows(bone.matrix),
                                              "matrix_basis": matrix_rows(bone.matrix_basis),
                                              "head": list(bone.head), "tail": list(bone.tail)}
                                  for bone in rig.pose.bones}})
    return {"frame": bpy.context.scene.frame_current, "armatures": records}, (rigs[0] if rigs else None)


def node_graph(tree):
    if tree is None:
        return None
    nodes = []
    for node in tree.nodes:
        item = {"name": node.name, "type": node.bl_idname,
                "inputs": [{"name": socket.name, "identifier": socket.identifier,
                            "default": serial(socket.default_value) if hasattr(socket, "default_value") else None}
                           for socket in node.inputs]}
        for attribute in ("operation", "blend_type", "distribution", "subsurface_method", "interpolation", "extension"):
            if hasattr(node, attribute):
                item[attribute] = serial(getattr(node, attribute))
        if getattr(node, "image", None):
            image = node.image
            path = Path(bpy.path.abspath(image.filepath)) if image.filepath else None
            item["image"] = {"name": image.name, "filepath": str(path) if path else None,
                             "external_sha256": sha256_file(path) if path and path.is_file() else None,
                             "packed": image.packed_file is not None}
        nodes.append(item)
    return {"nodes": sorted(nodes, key=lambda item: item["name"]),
            "links": sorted([link.from_node.name, link.from_socket.identifier,
                             link.to_node.name, link.to_socket.identifier] for link in tree.links)}


def material_state(body):
    return [{"slot": index, "use_nodes": material.use_nodes if material else False,
             "diffuse_color": list(material.diffuse_color) if material else None,
             "nodes": node_graph(material.node_tree) if material and material.use_nodes else None}
            for index, material in enumerate(body.data.materials)]


def lighting_state(scene):
    lights = []
    for obj in scene.objects:
        if obj.type != "LIGHT":
            continue
        data = obj.data
        receivers = obj.light_linking.receiver_collection
        lights.append({"name": obj.name, "matrix_world": matrix_rows(obj.matrix_world), "type": data.type,
                       "energy": data.energy, "color": list(data.color), "shape": getattr(data, "shape", None),
                       "size": getattr(data, "size", None), "size_y": getattr(data, "size_y", None),
                       "specular_factor": data.specular_factor, "visible_glossy": obj.visible_glossy,
                       "hide_render": obj.hide_render,
                       "receivers": sorted(item.name for item in receivers.objects) if receivers else None})
    return {"lights": sorted(lights, key=lambda item: item["name"]),
            "world": node_graph(scene.world.node_tree),
            "view": {"transform": scene.view_settings.view_transform, "look": scene.view_settings.look,
                     "exposure": scene.view_settings.exposure, "gamma": scene.view_settings.gamma}}


def aim(obj, target):
    direction = Vector(target) - obj.location
    if direction.length < 1e-6:
        raise ValueError("Camera/light location cannot equal its target")
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def configure(scene, body, out_dir, profile, native):
    # Copy before studio setup: restoring references alone is insufficient when
    # the setup routine rebuilds a source material with the same datablock name.
    original_copies = [material.copy() if material else None for material in body.data.materials] if native else []
    sys.path.insert(0, str(ROOT / "scripts"))
    from studio_v2 import setup_studio_v2
    cameras = setup_studio_v2(scene, out_dir, profile["studio"]["variant"])
    if native:
        body.data.materials.clear()
        for material in original_copies:
            body.data.materials.append(material)
    camera = cameras["Hero"]
    camera_config = profile["camera"]
    camera.location = camera_config["location"]
    aim(camera, camera_config["target"])
    camera.data.type = camera_config["type"]
    camera.data.ortho_scale = camera_config["ortho_scale"]
    camera.data.lens = camera_config["lens_mm"]
    camera.data.clip_start = camera_config["clip_start"]
    camera.data.clip_end = camera_config["clip_end"]
    camera.data.dof.use_dof = False
    camera.data.shift_x = camera.data.shift_y = 0
    scene.camera = camera
    for config in profile["lights"]:
        obj = bpy.data.objects[config["name"]]
        obj.location = config["location"]
        aim(obj, config["target"])
        obj.data.energy = config["energy"]
        obj.data.shape = "RECTANGLE"
        obj.data.size = config["width"]
        obj.data.size_y = config["height"]
        obj.data.color = config["color"]
    background = next(node for node in scene.world.node_tree.nodes if node.type == "BACKGROUND")
    background.inputs["Color"].default_value = profile["world"]["color"]
    background.inputs["Strength"].default_value = profile["world"]["strength"]
    for name, value in profile["color_management"].items():
        setattr(scene.view_settings, name, value)
    config = profile["render"]
    scene.render.engine = config["engine"]
    scene.cycles.device = config["device"]
    scene.cycles.samples = config["samples"]
    scene.cycles.seed = config["seed"]
    scene.cycles.use_animated_seed = False
    scene.cycles.use_adaptive_sampling = config["adaptive_sampling"]
    scene.cycles.use_denoising = config["beauty_denoising"]
    scene.render.resolution_x, scene.render.resolution_y = config["width"], config["height"]
    scene.render.resolution_percentage = 100
    scene.render.pixel_aspect_x, scene.render.pixel_aspect_y = config["pixel_aspect_x"], config["pixel_aspect_y"]
    scene.render.image_settings.file_format = config["format"]
    scene.render.image_settings.color_mode = config["color_mode"]
    scene.render.image_settings.color_depth = config["color_depth"]
    scene.render.film_transparent = False
    scene.render.use_border = False
    scene.render.use_compositing = False
    scene.render.use_sequencer = False
    scene.render.dither_intensity = 0
    bpy.context.view_layer.update()
    return camera


def project_landmarks(scene, camera, rig):
    results = {}
    width, height = scene.render.resolution_x, scene.render.resolution_y
    for joint, prefix in LANDMARK_BONES.items():
        pair = []
        for side in ("L", "R"):
            name = prefix + "." + side
            bone = rig.pose.bones.get(name) if rig else None
            if bone is None:
                pair.append({"anatomical_side": side, "source_bone": name, "available": False})
                continue
            point = rig.matrix_world @ bone.head
            projected = world_to_camera_view(scene, camera, point)
            x, y, depth = float(projected.x), float(1 - projected.y), float(projected.z)
            pair.append({"available": True, "x": x, "y": y, "pixel_x": x * width, "pixel_y": y * height,
                         "depth_m": depth, "in_front": depth > 0,
                         "in_frame": 0 <= x <= 1 and 0 <= y <= 1 and camera.data.clip_start <= depth <= camera.data.clip_end,
                         "world_xyz": list(point), "source_bone": name, "bone_endpoint": "head",
                         "anatomical_side": side, "rig_object": rig.name, "occlusion_tested": False})
        pair.sort(key=lambda item: item.get("x", math.inf))
        for screen_side, point in zip(("left", "right"), pair):
            point["screen_side_rule"] = "Pair sorted by projected X, independent of anatomical L/R"
            results[f"screen_{screen_side}_{joint}"] = point
    return results


def render_mask(scene, body, out_dir, profile):
    # A fresh emission material changes the scene only in memory. All body
    # modifiers, pose, camera, geometry and sample/AA settings stay unchanged.
    material = bpy.data.materials.new("GB_Calibration_GeometryMask")
    material.use_nodes = True
    material.node_tree.nodes.clear()
    emission = material.node_tree.nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (1, 1, 1, 1)
    emission.inputs["Strength"].default_value = 1
    output = material.node_tree.nodes.new("ShaderNodeOutputMaterial")
    material.node_tree.links.new(emission.outputs["Emission"], output.inputs["Surface"])
    body.data.materials.clear()
    body.data.materials.append(material)
    body.hide_render = False
    for obj in scene.objects:
        if obj != body and obj.type in {"MESH", "CURVE", "SURFACE", "META", "FONT", "VOLUME", "LIGHT"}:
            obj.hide_render = True
    background = next(node for node in scene.world.node_tree.nodes if node.type == "BACKGROUND")
    background.inputs["Color"].default_value = (0, 0, 0, 1)
    background.inputs["Strength"].default_value = 0
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0
    scene.view_settings.gamma = 1
    scene.cycles.use_denoising = profile["render"]["mask_denoising"]
    scene.render.filepath = str(out_dir / "mask.png")
    bpy.ops.render.render(write_still=True)


def main():
    if not bpy.app.background:
        raise RuntimeError("This collector requires a separate background Blender process")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blend", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--profile", type=Path, default=DEFAULT_PROFILE)
    parser.add_argument("--native-appearance", action="store_true")
    parser.add_argument("--camera-location", nargs=3, type=float)
    parser.add_argument("--camera-target", nargs=3, type=float)
    parser.add_argument("--ortho-scale", type=float)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    source, out_dir, profile_path = args.blend.resolve(), args.out.resolve(), args.profile.resolve()
    if not source.is_file() or source.suffix.lower() != ".blend":
        raise ValueError("--blend must identify an existing .blend file")
    if out_dir.exists() and (not out_dir.is_dir() or any(out_dir.iterdir())):
        raise FileExistsError("--out must be absent or an empty directory; no captures are overwritten")
    profile = json.loads(profile_path.read_text())
    effective = copy.deepcopy(profile)
    for attribute, key in (("camera_location", "location"), ("camera_target", "target"), ("ortho_scale", "ortho_scale")):
        value = getattr(args, attribute)
        if value is not None:
            effective["camera"][key] = value
    if effective["camera"]["ortho_scale"] <= 0:
        raise ValueError("Orthographic scale must be positive")
    dependencies = {relative: sha256_file(ROOT / relative) for relative in profile["code_dependencies"]}
    if dependencies != profile["code_dependencies"]:
        raise RuntimeError("Studio dependency changed. Review and update the capture profile hashes explicitly.")
    source_before = sha256_file(source)
    out_dir.mkdir(parents=True, exist_ok=True)
    capture = {"schema_version": 1, "status": "running", "created_at_utc": datetime.now(timezone.utc).isoformat(),
               "source_blend": str(source), "source_blend_sha256_before": source_before,
               "profile_path": str(profile_path), "profile_sha256": sha256_file(profile_path),
               "effective_profile_sha256": canonical_hash(effective), "effective_profile": effective,
               "native_appearance": args.native_appearance, "material_overridden": not args.native_appearance,
               "lighting_overridden": True, "camera_overridden": True,
               "track": "native-material_fixed-studio" if args.native_appearance else "geometry-and-pose_fixed-appearance",
               "code_dependencies": dependencies, "collector_sha256": sha256_file(__file__),
               "blender_version": bpy.app.version_string, "blender_build_hash": bpy.app.build_hash.decode(),
               "landmark_coordinate_system": "normalized [0,1], origin top-left; pixel coordinates are continuous width/height scaled",
               "landmark_visibility_limit": "in_frame/in_front are projection checks only. Bones lie inside the skin; silhouette occlusion and confidence are NOT measured.",
               "mask_method": "Real isolated visible-body emission render with antialiasing; no image color threshold. Floor and all other render geometry omitted.",
               "source_saved_by_collector": False}
    try:
        bpy.ops.wm.open_mainfile(filepath=str(source), load_ui=False, use_scripts=False)
        scene = bpy.context.scene
        scene.frame_set(effective["frame"])
        body = bpy.data.objects.get(effective["body_object"])
        if body is None or body.type != "MESH":
            raise RuntimeError("Profile body_object must name an existing mesh")
        if body.name != "GreenBody":
            raise RuntimeError("Selected3 studio currently expects the body object name GreenBody")
        geometry_before = geometry_state(body)
        pose_before, rig = pose_state(body)
        camera = configure(scene, body, out_dir, effective, args.native_appearance)
        geometry = geometry_state(body)
        pose, rig = pose_state(body)
        if geometry_before != geometry or canonical_hash(pose_before) != canonical_hash(pose):
            raise RuntimeError("Studio normalization unexpectedly changed geometry or pose")
        materials = material_state(body)
        lighting = lighting_state(scene)
        capture.update({"body_object": body.name, "geometry": geometry, "geometry_hash": canonical_hash(geometry),
                        "pose": pose, "pose_hash": canonical_hash(pose),
                        "materials": materials, "material_hash": canonical_hash(materials),
                        "lighting": lighting, "lighting_hash": canonical_hash(lighting),
                        "camera": {"object": camera.name, "type": camera.data.type, "location": list(camera.location),
                                   "target": effective["camera"]["target"], "matrix_world": matrix_rows(camera.matrix_world),
                                   "ortho_scale": camera.data.ortho_scale, "lens_mm": camera.data.lens,
                                   "clip_start": camera.data.clip_start, "clip_end": camera.data.clip_end},
                        "render": effective["render"], "landmarks": project_landmarks(scene, camera, rig),
                        "geometry_and_pose_unchanged_by_studio": True})
        scene.render.filepath = str(out_dir / "beauty.png")
        bpy.ops.render.render(write_still=True)
        render_mask(scene, body, out_dir, effective)
        capture["outputs"] = {name: {"path": str(out_dir / name), "sha256": sha256_file(out_dir / name)}
                              for name in ("beauty.png", "mask.png")}
        capture["status"] = "complete"
    except Exception as error:
        capture["status"] = "failed"
        capture["error"] = str(error)
        raise
    finally:
        capture["source_blend_sha256_after"] = sha256_file(source)
        capture["source_unchanged"] = capture["source_blend_sha256_after"] == source_before
        if not capture["source_unchanged"]:
            capture["status"] = "failed_source_changed"
        (out_dir / "capture.json").write_text(json.dumps(capture, indent=2, allow_nan=False))
    if not capture["source_unchanged"]:
        raise RuntimeError("Source file changed during capture; baseline is invalid")
    print("CALIBRATION_CAPTURE", out_dir / "capture.json", flush=True)


if __name__ == "__main__":
    main()
