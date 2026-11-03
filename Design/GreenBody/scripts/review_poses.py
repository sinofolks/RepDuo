"""One-pass static pose QA; not an animation or tracking implementation.

Only reads GreenBody-v1.blend. All generated review files stay in
renders/pose-tests. Run with a separate background Blender process.
"""

import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "renders" / "pose-tests"


def update():
    bpy.context.view_layer.update()


def rotate_world(bone, rotation):
    pivot = bone.head.copy()
    matrix = rotation.to_matrix().to_4x4() if isinstance(rotation, Quaternion) else rotation.to_4x4()
    bone.matrix = Matrix.Translation(pivot) @ matrix @ Matrix.Translation(-pivot) @ bone.matrix
    update()


def aim_chain(rig, first, endpoint, direction):
    bone = rig.pose.bones[first]
    current = rig.pose.bones[endpoint].head - bone.head
    rotate_world(bone, current.normalized().rotation_difference(Vector(direction).normalized()))


def set_world_rotation(bone, quaternion):
    matrix = quaternion.to_matrix().to_4x4()
    matrix.translation = bone.head.copy()
    bone.matrix = matrix
    update()


def palm_down(rig, side):
    wrist = rig.pose.bones["wrist." + side]
    forward = (rig.pose.bones["finger3-1." + side].head - wrist.head).normalized()
    across = rig.pose.bones["finger2-1." + side].head - rig.pose.bones["finger5-1." + side].head
    across = (across - forward * across.dot(forward)).normalized()
    normal = across.cross(forward).normalized()
    current = Matrix((across, forward, normal)).transposed()
    target_forward = Vector((0, -1, 0))
    target_across = Vector((-1 if side == "L" else 1, 0, 0))
    target_normal = target_across.cross(target_forward).normalized()
    target = Matrix((target_across, target_forward, target_normal)).transposed()
    rotate_world(wrist, target @ current.transposed())


def reset(rig):
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    update()


def root_pose(rig, tilt, height):
    root = rig.pose.bones["root"]
    rotate_world(root, Quaternion((1, 0, 0), math.radians(tilt)))
    matrix = root.matrix.copy()
    matrix.translation.z = height
    root.matrix = matrix
    update()


def squat(rig):
    root_pose(rig, 25, 0.56)
    for side, sign in (("L", 1), ("R", -1)):
        aim_chain(rig, "upperleg01." + side, "lowerleg01." + side, (sign * 0.16, -0.96, -0.17))
        aim_chain(rig, "lowerleg01." + side, "foot." + side, (sign * 0.035, 0.30, -0.955))
        foot = rig.pose.bones["foot." + side]
        set_world_rotation(foot, foot.bone.matrix_local.to_quaternion())
        aim_chain(rig, "upperarm01." + side, "lowerarm01." + side, (sign * 0.035, -1, -0.025))
        aim_chain(rig, "lowerarm01." + side, "wrist." + side, (sign * 0.015, -1, -0.020))
        palm_down(rig, side)


def push_up(rig):
    root_pose(rig, 90, 0.31)
    for side, sign in (("L", 1), ("R", -1)):
        aim_chain(rig, "upperleg01." + side, "lowerleg01." + side, (sign * 0.055, 1, -0.02))
        aim_chain(rig, "lowerleg01." + side, "foot." + side, (sign * 0.015, 1, -0.12))
        # Dorsiflexed forefoot with the toes pointing down into the support plane.
        foot = rig.pose.bones["foot." + side]
        rotation = Quaternion((1, 0, 0), math.radians(67)) @ foot.bone.matrix_local.to_quaternion()
        set_world_rotation(foot, rotation)
        aim_chain(rig, "upperarm01." + side, "lowerarm01." + side, (sign * 0.34, 0.91, -0.24))
        aim_chain(rig, "lowerarm01." + side, "wrist." + side, (-sign * 0.015, -0.29, -0.957))
        palm_down(rig, side)
    # Small cervical extension lets the face look ahead without lifting the torso.
    rotate_world(rig.pose.bones["neck01"], Quaternion((1, 0, 0), math.radians(-12)))
    # One correction pass: solve a common downward leg slope so both toe tips
    # meet the same support plane as the hands. This is not an IK controller.
    body = bpy.data.objects["GreenBody"]
    low, high = 0.02, 0.42
    for _ in range(8):
        slope = (low + high) / 2
        for side, sign in (("L", 1), ("R", -1)):
            aim_chain(rig, "upperleg01." + side, "lowerleg01." + side, (sign * 0.035, 1, -slope))
            aim_chain(rig, "lowerleg01." + side, "foot." + side, (sign * 0.015, 1, -slope))
            foot = rig.pose.bones["foot." + side]
            rotation = Quaternion((1, 0, 0), math.radians(67)) @ foot.bone.matrix_local.to_quaternion()
            set_world_rotation(foot, rotation)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        evaluated = body.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        toe_height = min(v.co.z for v in mesh.vertices if v.co.y > 0.70)
        hand_height = min(v.co.z for v in mesh.vertices if abs(v.co.x) > 0.20 and v.co.y < 0.05)
        evaluated.to_mesh_clear()
        if toe_height > hand_height:
            low = slope
        else:
            high = slope


def evaluated_bounds(body):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = body.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
    minimum = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    maximum = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    evaluated.to_mesh_clear()
    return minimum, maximum


def render_pose(name, pose_function):
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / "GreenBody-v1.blend"))
    scene = bpy.context.scene
    rig = bpy.data.objects["GB_ReviewArmature"]
    body = bpy.data.objects["GreenBody"]
    reset(rig)
    pose_function(rig)
    minimum, maximum = evaluated_bounds(body)
    root = rig.pose.bones["root"]
    matrix = root.matrix.copy()
    matrix.translation.z -= minimum.z
    root.matrix = matrix
    update()
    minimum, maximum = evaluated_bounds(body)
    center = (minimum + maximum) / 2
    camera = bpy.data.objects["GB_Camera_Hero"]
    if name == "squat":
        camera.location = center + Vector((3.7, -5.0, 1.0))
        camera.data.ortho_scale = 1.67
    else:
        camera.location = center + Vector((5.0, -2.0, 1.50))
        camera.data.ortho_scale = 2.55
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.render.resolution_x = 600
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.filepath = str(OUT / (name + ".png"))
    scene["pose_review_only"] = True
    scene["animation_approved"] = False
    scene["version"] = "Green Body — " + name + " static pose study; not animation approved"
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / (name + ".blend")))
    bpy.ops.render.render(write_still=True)
    report = {
        "status": "Static bone pose study only; no animation or camera tracking verification",
        "source_blend": str(ROOT / "GreenBody-v1.blend"),
        "bounds": {"minimum": list(minimum), "maximum": list(maximum)},
        "pose_bones": {n: {"head": list(b.head), "tail": list(b.tail), "matrix_basis": [list(row) for row in b.matrix_basis]}
                       for n, b in rig.pose.bones.items()},
    }
    (OUT / (name + "-pose.json")).write_text(json.dumps(report, indent=2))
    print("POSE_REVIEW", name, scene.render.filepath, flush=True)


if __name__ == "__main__":
    if not bpy.app.background:
        raise RuntimeError("Run in a separate background Blender process.")
    OUT.mkdir(parents=True, exist_ok=True)
    render_pose("squat", squat)
    render_pose("push-up", push_up)
