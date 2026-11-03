"""Blender-rendered comparison board: reference, actual v1, actual v2.

Only texture crops and uniform scaling are used. No repainting, generated
replacement details or warping of the model render is performed.
"""

from pathlib import Path

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def emission(name, color):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.node_tree.nodes.clear()
    shader = mat.node_tree.nodes.new("ShaderNodeEmission")
    shader.inputs["Color"].default_value = (*color, 1)
    output = mat.node_tree.nodes.new("ShaderNodeOutputMaterial")
    mat.node_tree.links.new(shader.outputs[0], output.inputs["Surface"])
    return mat, shader


def label(text, x, y, size, material):
    curve = bpy.data.curves.new(text, "FONT")
    curve.body = text
    curve.size = size
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    obj = bpy.data.objects.new(text, curve)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = (x, y, 0.05)
    obj.data.materials.append(material)


def panel(path, roi, x, title, subtitle, text_material, dim_material):
    image = bpy.data.images.load(str(path), check_existing=True)
    width, height = image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    rgb = pixels.reshape(height, width, 4)[::-1, :, :3]
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    mask = (g > 0.25) & (g > r * 1.06) & (g > b * 1.45)
    x0, y0, x1, y1 = roi
    region = np.zeros_like(mask)
    region[y0:y1, x0:x1] = True
    # Select the largest connected green component to avoid counting the
    # detached floor reflection as part of the character's height.
    remaining = (mask & region).ravel()
    largest = []
    for seed in np.flatnonzero(remaining):
        if not remaining[seed]:
            continue
        remaining[seed] = False
        stack, component = [int(seed)], []
        while stack:
            index = stack.pop()
            component.append(index)
            for neighbor in (index - width, index + width, index - 1, index + 1):
                if 0 <= neighbor < remaining.size and remaining[neighbor]:
                    remaining[neighbor] = False
                    stack.append(neighbor)
        if len(component) > len(largest):
            largest = component
    ys, xs = np.divmod(np.asarray(largest), width)
    assert len(xs) > 1000, f"Missing character mask: {path}"
    bounds = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    bx0, by0, bx1, by1 = bounds
    scale = 8.30 / (by1 - by0)
    left, right = max(0, bx0 - 16), min(width, bx1 + 16)
    top, bottom = max(0, by0 - 14), min(height, by1 + 16)
    panel_width, panel_height = (right - left) * scale, (bottom - top) * scale
    cy = -4.15 - (bottom - by1) * scale + panel_height / 2
    mesh = bpy.data.meshes.new(title)
    mesh.from_pydata([(x - panel_width/2, cy - panel_height/2, 0),
                      (x + panel_width/2, cy - panel_height/2, 0),
                      (x + panel_width/2, cy + panel_height/2, 0),
                      (x - panel_width/2, cy + panel_height/2, 0)], [], [(0, 1, 2, 3)])
    uv = mesh.uv_layers.new()
    coordinates = [(left/width, 1-bottom/height), (right/width, 1-bottom/height),
                   (right/width, 1-top/height), (left/width, 1-top/height)]
    for item, coordinate in zip(uv.data, coordinates):
        item.uv = coordinate
    obj = bpy.data.objects.new(title, mesh)
    bpy.context.scene.collection.objects.link(obj)
    material, shader = emission(title + " image", (1, 1, 1))
    texture = material.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = image
    material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Color"])
    mesh.materials.append(material)
    label(title, x, 4.91, 0.27, text_material)
    label(subtitle, x, 4.52, 0.15, dim_material)


def main():
    if not bpy.app.background:
        raise RuntimeError("Run in an independent background Blender process.")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 8
    scene.cycles.use_denoising = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0
    world = bpy.data.worlds.new("Comparison background")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.003, 0.004, 0.0035, 1)
    scene.world = world
    bright, _ = emission("Labels", (0.82, 0.85, 0.82))
    dim, _ = emission("Descriptions", (0.31, 0.35, 0.32))
    panel(ROOT / "reference/green-body-concept.png", (160, 74, 475, 828),
          -5.1, "REFERENCE", "Original AI concept", bright, dim)
    panel(ROOT / "renders/hero.png", (230, 95, 760, 1140),
          0, "V1", "Previous Blender model", bright, dim)
    panel(ROOT / "renders/v2/hero.png", (150, 70, 850, 1150),
          5.1, "V2", "Refined Blender model", bright, dim)
    label("Approximate height normalization  /  Uniform scale only  /  Actual Blender renders",
          0, -4.88, 0.15, dim)
    camera_data = bpy.data.cameras.new("Comparison")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 16.8
    camera = bpy.data.objects.new("Comparison", camera_data)
    scene.collection.objects.link(camera)
    camera.location = (0, 0, 10)
    scene.camera = camera
    scene.render.resolution_x = 1800
    scene.render.resolution_y = 1150
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.filepath = str(ROOT / "renders/v2/comparison.png")
    bpy.ops.render.render(write_still=True)
    print("V2_COMPARISON", scene.render.filepath, flush=True)


if __name__ == "__main__":
    main()
