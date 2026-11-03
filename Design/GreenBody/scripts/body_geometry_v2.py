"""Reference-led torso planes and natural review stance for Green Body v2."""

import math

import bpy
from mathutils import Matrix, Quaternion, Vector

from build_green_body import smoothstep, neutral_posture


def _sample(z, profile):
    if z <= profile[0][0]:
        return profile[0][1]
    for (low, a), (high, b) in zip(profile, profile[1:]):
        if z <= high:
            t = smoothstep(low, high, z)
            return a + (b - a) * t
    return profile[-1][1]


def refine_body(points):
    """Apply the same smooth coordinate map to body and joint helper points.

    The neck seam, overall height, hip width, leg lengths and ankle stance are
    preserved. Torso narrowing is local rather than globally slimming limbs.
    """
    profile = [(0.94, 1.0), (1.07, 0.96), (1.17, 0.94),
               (1.29, 0.96), (1.43, 0.935), (1.49, 0.95), (1.545, 1.0)]
    for point in points:
        x, y, z = point
        if z >= 1.545 or z <= 0.94:
            continue
        # Keep lateral arms almost unchanged while moving shoulder joints with
        # the torso. Falloff avoids an abrupt shoulder/arm boundary.
        central = 1 - smoothstep(0.20, 0.40, abs(x))
        point.x *= 1 + (_sample(z, profile) - 1) * central
        # Broader, flatter pectoral plates instead of round lower-chest pads.
        chest = math.exp(-0.5 * ((abs(point.x) - 0.075) / 0.085) ** 4)
        chest *= 1 - smoothstep(-0.11, -0.055, y)
        if chest > 0:
            # Analytic broad sculpt strokes retain the source surface flow;
            # avoid replacing it with stacked height-profile plateaus.
            upper_chest = -0.011 * math.exp(-0.5 * ((z - 1.393) / 0.048) ** 2)
            lower_pad = 0.006 * math.exp(-0.5 * ((z - 1.306) / 0.030) ** 2)
            point.y += (upper_chest + lower_pad) * chest
    return points


def _rotate(bone, rotation):
    pivot = bone.head.copy()
    matrix = rotation.to_matrix().to_4x4() if isinstance(rotation, Quaternion) else rotation.to_4x4()
    bone.matrix = Matrix.Translation(pivot) @ matrix @ Matrix.Translation(-pivot) @ bone.matrix
    bpy.context.view_layer.update()


def blend_neck_seam(body):
    """Locally remove the source/loft transition ridge without changing topology.

    Alternating Taubin passes limit the shrinkage of ordinary Laplacian
    smoothing. Existing skin groups and every face index remain unchanged.
    """
    mesh = body.data
    neighbors = [[] for _ in mesh.vertices]
    for edge in mesh.edges:
        a, b = edge.vertices
        neighbors[a].append(b)
        neighbors[b].append(a)
    weights = {}
    for vertex in mesh.vertices:
        z = vertex.co.z
        weight = smoothstep(1.525, 1.55, z) * (1 - smoothstep(1.588, 1.615, z))
        if weight > 0:
            weights[vertex.index] = weight
    for _ in range(9):
        for rate in (0.48, -0.50):
            positions = [vertex.co.copy() for vertex in mesh.vertices]
            for index, weight in weights.items():
                adjacent = neighbors[index]
                if adjacent:
                    mean = sum((positions[n] for n in adjacent), Vector()) / len(adjacent)
                    mesh.vertices[index].co += (mean - positions[index]) * rate * weight
    mesh.update()


def review_posture(rig):
    neutral_posture(rig)
    for side, sign in (("L", 1), ("R", -1)):
        # Reference: near foot toward camera, far foot visibly turned outward.
        foot = rig.pose.bones["foot." + side]
        degrees = 46 if side == "L" else -15
        rotation = Quaternion((0, 0, 1), math.radians(degrees))
        matrix = (rotation @ foot.bone.matrix_local.to_quaternion()).to_matrix().to_4x4()
        matrix.translation = foot.head.copy()
        foot.matrix = matrix
        bpy.context.view_layer.update()

        wrist = rig.pose.bones["wrist." + side]
        forward = (rig.pose.bones["finger3-1." + side].head - wrist.head).normalized()
        across = rig.pose.bones["finger2-1." + side].head - rig.pose.bones["finger5-1." + side].head
        across = (across - forward * across.dot(forward)).normalized()
        current = Matrix((across, forward, across.cross(forward))).transposed()
        desired_forward = Vector((sign * 0.03, -0.16, -1)).normalized()
        desired_across = Vector((-sign * 0.50, -0.86, 0))
        desired_across = (desired_across - desired_forward * desired_across.dot(desired_forward)).normalized()
        target = Matrix((desired_across, desired_forward,
                         desired_across.cross(desired_forward))).transposed()
        _rotate(wrist, target @ current.transposed())
        # Relaxed, small progressive finger flexion. Keep thumb separation and
        # individual fingertips rather than scaling the entire hand.
        for finger in (2, 3, 4, 5):
            first = rig.pose.bones.get(f"finger{finger}-1.{side}")
            if first:
                direction = (first.tail - first.head).normalized()
                closed_spread = (direction * 0.25 + desired_forward * 0.75).normalized()
                _rotate(first, direction.rotation_difference(closed_spread))
            for segment, angle in ((1, 4), (2, 12), (3, 8)):
                bone = rig.pose.bones.get(f"finger{finger}-{segment}.{side}")
                if bone:
                    _rotate(bone, Quaternion(desired_across, math.radians(-angle * sign)))
    bpy.context.view_layer.update()
