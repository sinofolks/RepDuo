"""V2 continuous mannequin head; isolated geometry and actual-render study.

The import interface is rebuild_head(body). The main application and v1 asset
are never overwritten. All candidate evidence goes below v2-experiments.
"""

import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "renders" / "v2-experiments"


def smoothstep(low, high, value):
    t = min(1.0, max(0.0, (value - low) / (high - low)))
    return t * t * (3 - 2 * t)


def gaussian(value, center, width):
    return math.exp(-0.5 * ((value - center) / width) ** 2)


def rebuild_head(body):
    cut_z = 1.556
    original_body = sorted(tuple(v.co) for v in body.data.vertices if v.co.z < cut_z - 1e-5)
    mesh = bmesh.new()
    mesh.from_mesh(body.data)
    bmesh.ops.bisect_plane(mesh, geom=list(mesh.verts) + list(mesh.edges) + list(mesh.faces),
                          dist=1e-6, plane_co=(0, 0, cut_z), plane_no=(0, 0, 1),
                          clear_outer=True, clear_inner=False)
    boundary = {v for e in mesh.edges if e.is_boundary for v in e.verts}
    assert boundary and all(abs(v.co.z - cut_z) < 1e-4 for v in boundary)
    center = sum((v.co for v in boundary), Vector()) / len(boundary)
    ring = sorted(boundary, key=lambda v: math.atan2(v.co.y - center.y, v.co.x - center.x))
    originals = [v.co.copy() for v in ring]
    rx_start = max(abs(v.co.x) for v in boundary)
    front_start = min(v.co.y for v in boundary)
    back_start = max(v.co.y for v in boundary)
    ry_start = (back_start - front_start) / 2
    cy_start = (back_start + front_start) / 2
    # New upper-head rings use consistent samples. The actual cut boundary
    # remains entirely untouched, with a smooth neck-only correspondence blend.
    first_angle = math.atan2((originals[0].y - cy_start) / ry_start, originals[0].x / rx_start)
    angles = [first_angle + i * 2 * math.pi / len(ring) for i in range(len(ring))]
    profiles = [
        # Height, half-width, anterior contour, posterior contour.
        (cut_z, rx_start, front_start, back_start),
        (1.570, 0.0530, -0.0880, 0.0240),
        (1.589, 0.0470, -0.0910, 0.0290),
        (1.605, 0.0475, -0.1150, 0.0340),
        (1.617, 0.0540, -0.1280, 0.0390),
        (1.632, 0.0630, -0.1320, 0.0480),
        (1.655, 0.0725, -0.1300, 0.0590),
        (1.675, 0.0780, -0.1300, 0.0640),
        (1.696, 0.0805, -0.1310, 0.0640),
        (1.720, 0.0810, -0.1330, 0.0590),
    ]

    def sample(z, channel):
        i = next((i for i in range(len(profiles) - 1)
                  if profiles[i][0] <= z <= profiles[i + 1][0]), len(profiles) - 2)
        left, right = profiles[i], profiles[i + 1]
        span = right[0] - left[0]
        t = (z - left[0]) / span
        p0, p1 = left[channel], right[channel]
        def tangent(index):
            if index == len(profiles) - 1:
                # Match the dome's horizontal derivative at its equator.
                return 0.0
            if index == 0:
                return (profiles[1][channel] - profiles[0][channel]) / (profiles[1][0] - profiles[0][0])
            before, current, after = profiles[index - 1:index + 2]
            h0, h1 = current[0] - before[0], after[0] - current[0]
            d0, d1 = (current[channel] - before[channel]) / h0, (after[channel] - current[channel]) / h1
            if d0 * d1 <= 0:
                return 0.0
            w0, w1 = 2 * h1 + h0, h1 + 2 * h0
            return (w0 + w1) / (w0 / d0 + w1 / d1)
        # One shared derivative per knot, not independent interval clamps:
        # avoids horizontal shading seams at profile joins.
        m0, m1 = tangent(i), tangent(i + 1)
        return ((2*t**3 - 3*t*t + 1)*p0 + (t**3 - 2*t*t + t)*span*m0
                + (-2*t**3 + 3*t*t)*p1 + (t**3 - t*t)*span*m1)

    deform = mesh.verts.layers.deform.active
    assert deform is not None
    head_group = body.vertex_groups["head"].index
    neck_group = body.vertex_groups["neck03"].index
    for step in range(1, 77):
        z = cut_z + (1.8198 - cut_z) * step / 76
        if z <= 1.720:
            rx, front, back = sample(z, 1), sample(z, 2), sample(z, 3)
        else:
            dome = math.sqrt(max(1e-8, 1 - ((z - 1.720) / 0.100) ** 2))
            rx = 0.081 * dome
            front, back = -0.037 - 0.096 * dome, -0.037 + 0.096 * dome
        # A single ellipsoidal cranium carries the sides/back through the
        # forehead. This avoids a cylinder-to-cap curvature change appearing
        # as a horizontal "helmet" band in the rear review camera.
        cranial_blend = smoothstep(1.642, 1.672, z)
        cranial_arc = math.sqrt(max(1e-8, 1 - ((z - 1.705) / 0.115) ** 2))
        rx += (0.082 * cranial_arc - rx) * cranial_blend
        back += (-0.038 + 0.101 * cranial_arc - back) * cranial_blend
        cy = (front + back) / 2
        new_ring = []
        for index, angle in enumerate(angles):
            x = rx * math.cos(angle)
            sine = math.sin(angle)
            front_mask = smoothstep(0.03, 0.43, -sine)
            if sine < 0:
                # Wider front facial plane, tapering into small jaw corners.
                exponent = 0.74 - 0.08 * gaussian(z, 1.637, 0.022)
                y = cy - (cy - front) * (-sine) ** exponent
                # Matched shallow orbital bowls, covered by a continuous surface.
                sockets = gaussian(x, 0.029, 0.014) + gaussian(x, -0.029, 0.014)
                y += 0.0012 * sockets * gaussian(z, 1.698, 0.0120) * front_mask
                brows = gaussian(x, 0.029, 0.019) + gaussian(x, -0.029, 0.019)
                y -= 0.00035 * brows * gaussian(z, 1.713, 0.0100) * front_mask
                # An unbroken nose ridge and a small rounded nasal tip.
                y -= 0.0050 * gaussian(x, 0, 0.011) * gaussian(z, 1.698, 0.020) * front_mask
                y -= 0.0105 * gaussian(x, 0, 0.015) * gaussian(z, 1.679, 0.0125) * front_mask
                # Cheek pads stop the face reading as a flat visor; no mouth line.
                cheeks = gaussian(x, 0.042, 0.015) + gaussian(x, -0.042, 0.015)
                y -= 0.0025 * cheeks * gaussian(z, 1.677, 0.017) * front_mask
                y -= 0.0014 * gaussian(x, 0, 0.026) * gaussian(z, 1.625, 0.012) * front_mask
            else:
                y = cy + (back - cy) * sine
            # Ear shell is sculpted within this same closed surface. Its small
            # rim projects farther than the concha, giving a thin ear, not a ball.
            side_mask = smoothstep(0.76, 0.94, abs(math.cos(angle)))
            ear_y = -0.011 + 0.11 * (z - 1.686)
            radial = math.sqrt(((y - ear_y) / 0.018) ** 2 + ((z - 1.686) / 0.027) ** 2)
            ear_mask = (1 - smoothstep(0.78, 1.08, radial)) * side_mask
            extension = 0.0080 * ear_mask
            extension += 0.0026 * gaussian(radial, 0.73, 0.18) * ear_mask
            extension -= 0.0028 * gaussian(radial, 0, 0.38) * ear_mask
            x += math.copysign(extension, x)
            # Preserve the actual boundary, then smoothly adopt the planned neck.
            join = smoothstep(cut_z, 1.592, z)
            x = originals[index].x * (1 - join) + x * join
            y = originals[index].y * (1 - join) + y * join
            vertex = mesh.verts.new((x, y, z))
            weight = smoothstep(cut_z, 1.624, z)
            vertex[deform][head_group] = weight
            vertex[deform][neck_group] = 1 - weight
            new_ring.append(vertex)
        for i in range(len(ring)):
            j = (i + 1) % len(ring)
            mesh.faces.new((ring[i], ring[j], new_ring[j], new_ring[i]))
        ring = new_ring
    mesh.faces.new(ring)
    for face in mesh.faces:
        face.smooth = True
    bmesh.ops.recalc_face_normals(mesh, faces=list(mesh.faces))
    assert all(edge.is_manifold for edge in mesh.edges)
    mesh.to_mesh(body.data)
    mesh.free()
    unchanged = sorted(tuple(v.co) for v in body.data.vertices if v.co.z < cut_z - 1e-5)
    assert original_body == unchanged, "Head replacement changed lower body geometry"
    body["head_design"] = "V2 continuous human mannequin: broader cranium, orbital/brow planes, nasal ridge, jaw and ear relief"


def main():
    if not bpy.app.background:
        raise RuntimeError("Use a separate background Blender, preserving the open scene.")
    OUT.mkdir(parents=True, exist_ok=True)
    body = bpy.data.objects["GreenBody"]
    rebuild_head(body)
    sys.path.insert(0, str(ROOT / "scripts"))
    from validate_green_body import check_original_mesh, check_armature_weights
    report = {"errors": [], "warnings": [], "scope": "Head v2 isolated candidate, body unchanged below z=1.556"}
    check_original_mesh(body, report)
    check_armature_weights(body, report)
    (OUT / "head-v2-refined-validation.json").write_text(json.dumps(report, indent=2))
    assert not report["errors"], report["errors"]
    assert report["original_mesh"]["connected_component_count"] == 1
    assert report["original_mesh"]["boundary_edge_count"] == 0
    scene = bpy.context.scene
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.render.resolution_x = 600
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    hero = bpy.data.objects["GB_Camera_Hero"]
    hero.location.x = -abs(hero.location.x)
    hero.rotation_euler = (Vector((0, 0, 0.94)) - hero.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = hero
    scene["version"] = "Head v2 isolated static appearance candidate"
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "head-v2-refined.blend"))
    scene.render.filepath = str(OUT / "head-v2-refined-hero.png")
    bpy.ops.render.render(write_still=True)
    target = Vector((0, -0.026, 1.639))
    for label, offset in (("closeup", (-1.70, -5.0, 0.15)), ("side", (-5.0, 0, 0.04))):
        hero.location = target + Vector(offset)
        hero.data.ortho_scale = 0.57
        hero.rotation_euler = (target - hero.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(OUT / ("head-v2-refined-" + label + ".png"))
        bpy.ops.render.render(write_still=True)
        print("HEAD_V2_REVIEW", scene.render.filepath, flush=True)


if __name__ == "__main__":
    main()
