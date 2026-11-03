"""Continuous stylized head geometry, selected after a two-angle visual review.

Import rebuild_head from the main builder. Running this module directly with
an already loaded model writes a separate experimental candidate and previews;
it never overwrites the main model. The loft preserves lower body coordinates.
"""

import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "renders" / "experiments"


def smoothstep(low, high, value):
    t = min(1.0, max(0.0, (value - low) / (high - low)))
    return t * t * (3.0 - 2.0 * t)


def rebuild_head(body):
    cut_z = 1.556
    unchanged_body = sorted(tuple(vertex.co) for vertex in body.data.vertices if vertex.co.z < cut_z - 1e-5)
    mesh = bmesh.new()
    mesh.from_mesh(body.data)
    bmesh.ops.bisect_plane(mesh, geom=list(mesh.verts) + list(mesh.edges) + list(mesh.faces),
                          dist=1e-6, plane_co=(0, 0, cut_z), plane_no=(0, 0, 1),
                          clear_outer=True, clear_inner=False)
    boundary = {vertex for edge in mesh.edges if edge.is_boundary for vertex in edge.verts}
    assert boundary and all(abs(vertex.co.z - cut_z) < 1e-4 for vertex in boundary)
    center = sum((vertex.co for vertex in boundary), Vector()) / len(boundary)
    ring = sorted(boundary, key=lambda vertex: math.atan2(vertex.co.y - center.y, vertex.co.x - center.x))
    original = [vertex.co.copy() for vertex in ring]
    first_angle = math.atan2((original[0].y - center.y) / 0.054, (original[0].x - center.x) / 0.044)
    angles = [first_angle + index * 2.0 * math.pi / len(ring) for index in range(len(ring))]

    # Independent front and back contours give a restrained jaw/forehead plane,
    # instead of pushing the whole front hemisphere into an egg-like profile.
    # Entries: height, half-width, front-most Y, back-most Y.
    profiles = [
        (cut_z, 0.044, center.y - 0.054, center.y + 0.054),
        (1.580, 0.043, -0.084, 0.025),
        (1.600, 0.045, -0.091, 0.027),
        (1.616, 0.051, -0.119, 0.035),
        (1.630, 0.058, -0.132, 0.045),
        (1.648, 0.065, -0.130, 0.053),
        (1.670, 0.071, -0.126, 0.059),
        (1.695, 0.075, -0.128, 0.061),
        (1.720, 0.076, -0.130, 0.058),
        (1.744, 0.074, -0.128, 0.053),
    ]

    def sample(z, channel):
        index = next((i for i in range(len(profiles) - 1)
                      if profiles[i][0] <= z <= profiles[i + 1][0]), len(profiles) - 2)
        t = (z - profiles[index][0]) / (profiles[index + 1][0] - profiles[index][0])
        p0 = profiles[max(0, index - 1)][channel]
        p1, p2 = profiles[index][channel], profiles[index + 1][channel]
        p3 = profiles[min(len(profiles) - 1, index + 2)][channel]
        return 0.5 * (2 * p1 + (-p0 + p2) * t
                      + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                      + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t)

    deform = mesh.verts.layers.deform.active
    head_index = body.vertex_groups["head"].index
    neck_index = body.vertex_groups["neck03"].index
    for step in range(1, 61):
        z = cut_z + (1.8197 - cut_z) * step / 60
        if z <= 1.744:
            rx, front, back = sample(z, 1), sample(z, 2), sample(z, 3)
        else:
            # True elliptical dome: broad rounded scalp, not a linear cone cap.
            dome = math.sqrt(max(1e-6, 1 - ((z - 1.744) / 0.076) ** 2))
            rx = 0.074 * dome
            front, back = -0.0375 - 0.0905 * dome, -0.0375 + 0.0905 * dome
        cy = (front + back) * 0.5
        next_ring = []
        for index, angle in enumerate(angles):
            x = rx * math.cos(angle)
            sine = math.sin(angle)
            if sine < 0:
                y = cy - (cy - front) * (-sine) ** 0.70
                # Soft nose and bridge without a mouth seam or eye cavities.
                y -= 0.012 * math.exp(-0.5 * (x / 0.016) ** 2 - 0.5 * ((z - 1.677) / 0.012) ** 2)
                y -= 0.0035 * math.exp(-0.5 * (x / 0.018) ** 2 - 0.5 * ((z - 1.703) / 0.023) ** 2)
                y -= 0.0025 * math.exp(-0.5 * (x / 0.034) ** 2 - 0.5 * ((z - 1.631) / 0.010) ** 2)
            else:
                y = cy + (back - cy) * sine
            # Small ear silhouettes are deformations of the same closed surface.
            # No separate spheres, boolean seams, or disconnected accessories.
            ear_angle = 0.35 if math.cos(angle) >= 0 else math.pi - 0.35
            distance = math.atan2(math.sin(angle - ear_angle), math.cos(angle - ear_angle))
            ear = 0.0105 * math.exp(-0.5 * (distance / 0.24) ** 2
                                     -0.5 * ((z - 1.688) / 0.023) ** 4)
            x += math.copysign(ear, x)
            blend = smoothstep(cut_z, 1.605, z)
            x = original[index].x * (1 - blend) + x * blend
            y = original[index].y * (1 - blend) + y * blend
            vertex = mesh.verts.new((x, y, z))
            head_weight = smoothstep(cut_z, 1.624, z)
            vertex[deform][head_index] = head_weight
            vertex[deform][neck_index] = 1 - head_weight
            next_ring.append(vertex)
        for index in range(len(ring)):
            following = (index + 1) % len(ring)
            mesh.faces.new((ring[index], ring[following], next_ring[following], next_ring[index]))
        ring = next_ring
    mesh.faces.new(ring)
    for face in mesh.faces:
        face.smooth = True
    bmesh.ops.recalc_face_normals(mesh, faces=list(mesh.faces))
    assert all(edge.is_manifold for edge in mesh.edges), "Candidate must remain manifold"
    mesh.to_mesh(body.data)
    mesh.free()
    after = sorted(tuple(vertex.co) for vertex in body.data.vertices if vertex.co.z < cut_z - 1e-5)
    assert unchanged_body == after, "Body below the head cutoff must be unchanged"
    body["head_design"] = "Continuous stylized head: anatomical front/back silhouette, shallow nose and ear relief"


def main():
    if not bpy.app.background:
        raise RuntimeError("Run in separate background Blender; preserve the user's open scene.")
    OUT.mkdir(parents=True, exist_ok=True)
    body = bpy.data.objects["GreenBody"]
    rebuild_head(body)
    scene = bpy.context.scene
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.render.resolution_x = 600
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.camera = bpy.data.objects["GB_Camera_Hero"]
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "head-candidate.blend"))
    for label in ("Hero", "Side"):
        scene.camera = bpy.data.objects["GB_Camera_" + label]
        scene.render.filepath = str(OUT / ("head-candidate-" + label.lower() + ".png"))
        bpy.ops.render.render(write_still=True)
        print("HEAD_CANDIDATE_RENDER", scene.render.filepath, flush=True)


if __name__ == "__main__":
    main()
