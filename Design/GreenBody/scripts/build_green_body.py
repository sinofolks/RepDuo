"""Create the review-only Green Body asset in a fresh, background Blender.

All geometry sources are CC0 MakeHuman data, not MakeHuman application code.
Run with Blender --background --factory-startup --python this_file -- --preview.
This script never edits RepDuo application files or Blender user preferences.
"""

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from studio import lime_material, setup_studio
from head_geometry import rebuild_head


def read_source():
    coordinates, faces = [], []
    group = None
    with (ROOT / "source/makehuman-base.obj").open() as stream:
        for line in stream:
            bits = line.split()
            if not bits:
                continue
            if bits[0] == "v":
                coordinates.append(Vector(tuple(map(float, bits[1:4]))))
            elif bits[0] == "g":
                group = bits[1]
            elif bits[0] == "f" and group == "body":
                faces.append(tuple(int(item.split("/")[0]) - 1 for item in bits[1:]))
    assert len(coordinates) == 19158 and len(faces) == 13378
    for filename, influence in [("adult-male.target", 1.0),
                                ("lean-tone.target", 0.22),
                                ("ideal-proportions.target", 0.38),
                                ("eye-left-closure.target", 1.0),
                                ("eye-right-closure.target", 1.0),
                                ("nose-scale-depth-decr.target", 0.55),
                                ("mouth-upperlip-volume-decr.target", 0.75),
                                ("mouth-lowerlip-volume-decr.target", 0.75),
                                ("l-ear-scale-decr.target", 0.40),
                                ("r-ear-scale-decr.target", 0.40)]:
        with (ROOT / "source" / filename).open() as stream:
            for line in stream:
                bits = line.split()
                if len(bits) != 4 or bits[0].startswith("#"):
                    continue
                index = int(bits[0])
                coordinates[index] += Vector(tuple(map(float, bits[1:]))) * influence
    points = [Vector((p.x * 0.1, -p.z * 0.1, p.y * 0.1)) for p in coordinates]
    used = sorted({i for face in faces for i in face})
    assert used == list(range(13380))
    floor = min(points[i].z for i in used)
    height = max(points[i].z for i in used) - floor
    scale = 1.82 / height
    for p in points:
        p.z -= floor
        p *= scale
        # Slender, non-bodybuilder silhouette; keep head width independent.
        head_weight = smoothstep(1.56, 1.66, p.z)
        p.x *= 0.92 * (1.0 + 0.09 * head_weight)
        p.y *= 0.96 * (1.0 + 0.05 * head_weight)
        p.z += 0.085 * head_weight * (p.z - 1.56)
    final_scale = 1.82 / max(points[i].z for i in used)
    points = [p * final_scale for p in points]
    # Replace expression grooves with a restrained convex mannequin face.
    # This continuous coordinate morph preserves the original quad topology.
    for p in points:
        weight = smoothstep(1.545, 1.580, p.z) * (1.0 - smoothstep(1.745, 1.785, p.z))
        weight *= 1.0 - smoothstep(0.055, 0.080, abs(p.x))
        weight *= 1.0 - smoothstep(-0.100, -0.060, p.y)
        radial = 1.0 - (p.x / 0.087) ** 2 - ((p.z - 1.70) / 0.137) ** 2
        if weight > 0 and radial > 0:
            target_y = -0.053 - 0.107 * math.sqrt(radial)
            target_y -= 0.004 * math.exp(-0.5 * (p.x / 0.014) ** 2 - 0.5 * ((p.z - 1.66) / 0.021) ** 2)
            p.y += (target_y - p.y) * weight
    return points, faces


def smoothstep(low, high, value):
    t = max(0.0, min(1.0, (value - low) / (high - low)))
    return t * t * (3.0 - 2.0 * t)


def make_rig(points, collection):
    spec = json.loads((ROOT / "source/default.mhskel").read_text())
    joints = {key: sum((points[i] for i in indices), Vector()) / len(indices)
              for key, indices in spec["joints"].items()}
    data = bpy.data.armatures.new("GB_ReviewArmature_Data")
    rig = bpy.data.objects.new("GB_ReviewArmature", data)
    collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, info in spec["bones"].items():
        bone = data.edit_bones.new(name)
        bone.head = joints[info["head"]]
        bone.tail = joints[info["tail"]]
        if (bone.tail - bone.head).length < 1e-6:
            bone.tail.z += 0.001
        plane_name = info.get("rotation_plane")
        if isinstance(plane_name, str) and plane_name in spec["planes"]:
            a, b, c = [joints[j] for j in spec["planes"][plane_name]]
            normal = (b - a).cross(c - a)
            if normal.length > 1e-6:
                bone.align_roll(normal)
    for name, info in spec["bones"].items():
        parent = info.get("parent")
        if parent and parent in data.edit_bones:
            data.edit_bones[name].parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.select_set(False)
    rig.show_in_front = True
    rig.display_type = "WIRE"
    rig["purpose"] = "Neutral review posing only; workout deformation is not approved."
    return rig, joints


def assign_weights(body, rig):
    weights = json.loads((ROOT / "source/default_weights.mhw").read_text())["weights"]
    total = [0.0] * len(body.data.vertices)
    for bone_name, values in weights.items():
        group = body.vertex_groups.new(name=bone_name)
        for index, value in values:
            if index < len(total) and value > 0:
                group.add([index], value, "REPLACE")
                total[index] += value
    for vertex in body.data.vertices:
        if total[vertex.index] > 0:
            for assignment in vertex.groups:
                group = body.vertex_groups[assignment.group]
                group.add([vertex.index], assignment.weight / total[vertex.index], "REPLACE")
    assert all(value > 0 for value in total), "Unweighted visible body vertices"
    modifier = body.modifiers.new("Review posture — preserve volume", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    return weights


def neutral_posture(rig):
    for side in ("L", "R"):
        bone = rig.pose.bones.get("upperarm01." + side)
        if bone:
            direction = bone.bone.tail_local - bone.bone.head_local
            sign = 1.0 if direction.x > 0 else -1.0
            rest = bone.bone.matrix_local.to_quaternion()
            bone.rotation_mode = "QUATERNION"
            bone.rotation_quaternion = rest.inverted() @ Quaternion((0, 1, 0), math.radians(25) * sign) @ rest
        forearm = rig.pose.bones.get("lowerarm01." + side)
        wrist = rig.data.bones.get("wrist." + side)
        if bone and forearm and wrist:
            upper_direction = (forearm.bone.head_local - bone.bone.head_local).normalized()
            forearm_direction = (wrist.head_local - forearm.bone.head_local).normalized()
            desired = (upper_direction + Vector((0, -0.12, 0))).normalized()
            rotation = forearm_direction.rotation_difference(desired)
            rest = forearm.bone.matrix_local.to_quaternion()
            forearm.rotation_mode = "QUATERNION"
            forearm.rotation_quaternion = rest.inverted() @ rotation @ rest
    bpy.context.view_layer.update()


def select_device(scene):
    preferences = bpy.context.preferences.addons["cycles"].preferences
    try:
        preferences.compute_device_type = "METAL"
        preferences.get_devices()
        gpu = False
        for device in preferences.devices:
            device.use = device.type == "METAL"
            gpu = gpu or device.use
        scene.cycles.device = "GPU" if gpu else "CPU"
    except Exception:
        scene.cycles.device = "CPU"


def main():
    if not bpy.app.background:
        raise RuntimeError("Run in a separate background Blender to preserve open user work.")
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--gpu", action="store_true")
    parser.add_argument("--render", default="Hero")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    points, faces = read_source()
    collection = bpy.data.collections.new("GB_Character")
    bpy.context.scene.collection.children.link(collection)
    mesh = bpy.data.meshes.new("GB_ContinuousBody_Quads")
    mesh.from_pydata([tuple(p) for p in points[:13380]], [], faces)
    mesh.update()
    body = bpy.data.objects.new("GreenBody", mesh)
    collection.objects.link(body)
    for face in mesh.polygons:
        face.use_smooth = True
    body.data.materials.append(lime_material())
    rig, joints = make_rig(points, collection)
    assign_weights(body, rig)
    rebuild_head(body)
    neutral_posture(rig)
    smooth = body.modifiers.new("Surface polish", "CORRECTIVE_SMOOTH")
    smooth.factor = 0.18
    smooth.iterations = 4
    smooth.use_pin_boundary = True
    subd = body.modifiers.new("Presentation subdivision", "SUBSURF")
    subd.levels = 2
    subd.render_levels = 2
    body["source"] = "MakeHuman hm08 CC0; customized proportions and material"
    body["status"] = "Static appearance study — no iOS integration"
    scene = bpy.context.scene
    cameras = setup_studio(scene, ROOT / "renders")
    if args.gpu:
        select_device(scene)
    scene.camera = cameras[args.render]
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    scene["reference"] = str(ROOT / "reference/green-body-concept.png")
    scene["approved_for_animation"] = False
    scene["version"] = "Green Body v1 — appearance review"
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                space = area.spaces.active
                space.shading.type = "SOLID"
                space.shading.color_type = "MATERIAL"
                space.overlay.show_overlays = False
                space.region_3d.view_perspective = "CAMERA"
    report = {
        "blender_version": bpy.app.version_string,
        "base_vertices": len(mesh.vertices), "base_faces": len(mesh.polygons),
        "source_license": "CC0-1.0", "height_m": 1.82,
        "bones": len(rig.data.bones), "animation_approved": False,
        "head_design": body["head_design"],
        "bone_positions": {n: {"head": list(b.head_local), "tail": list(b.tail_local)}
                           for n, b in rig.data.bones.items()
                           if n in ["head", "neck01", "upperarm01.L", "upperarm01.R", "lowerarm01.L", "upperleg01.L", "lowerleg01.L"]},
    }
    (ROOT / "model-report.json").write_text(json.dumps(report, indent=2))
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "GreenBody-v1.blend"))
    if args.preview:
        scene.render.resolution_percentage = 60
        scene.cycles.samples = 16
    scene.render.filepath = str(ROOT / "renders" / ("preview-" + args.render.lower() + ".png" if args.preview else args.render.lower() + ".png"))
    bpy.ops.render.render(write_still=True)
    print("GREEN_BODY_RENDER", scene.render.filepath, flush=True)


if __name__ == "__main__":
    main()
