"""Self-contained, meter-scale studio for the RepDuo green-body prototype.

The character is expected to be approximately 1.80 m tall, standing on Z=0,
centered at X=Y=0, with its face pointing toward -Y. Import this file from a
Blender build script, call ``lime_material()`` for the character material, then
``setup_studio(bpy.context.scene, output_directory)``. Nothing is rendered on
import and no Blender user preferences are changed.
"""

from pathlib import Path

import bpy
from mathutils import Vector


COLLECTION_NAME = "GB_Studio"


def _linear_channel(value):
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def _hex_linear(hex_color):
    """Convert an sRGB hex swatch to Blender's scene-linear RGBA values."""
    text = hex_color.lstrip("#")
    channels = [int(text[index:index + 2], 16) / 255.0 for index in (0, 2, 4)]
    return tuple(_linear_channel(channel) for channel in channels) + (1.0,)


def _set_input(node, names, value):
    for name in names:
        if name in node.inputs:
            node.inputs[name].default_value = value
            return


def lime_material():
    """Return the clean, non-metallic #B4F20B satin-lime character material.

    The color is a pigment rather than an emission shader: joints and surfaces
    remain legible under neutral lighting instead of glowing into a flat shape.
    """
    name = "GB_Lime_Satin"
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = _hex_linear("#B4F20B")
    material.node_tree.nodes.clear()
    shader = material.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
    shader.name = "Lime Satin — Principled"
    shader.location = (0, 0)
    shader.inputs["Base Color"].default_value = _hex_linear("#B4F20B")
    shader.inputs["Metallic"].default_value = 0.0
    shader.inputs["Roughness"].default_value = 0.48
    shader.inputs["IOR"].default_value = 1.44
    _set_input(shader, ("Specular IOR Level", "Specular"), 0.17)
    _set_input(shader, ("Coat Weight", "Clearcoat"), 0.0)
    _set_input(shader, ("Coat Roughness", "Clearcoat Roughness"), 0.38)
    _set_input(shader, ("Subsurface Weight", "Subsurface"), 0.0)
    output = material.node_tree.nodes.new("ShaderNodeOutputMaterial")
    output.location = (360, 0)
    material.node_tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    return material


def _collection(scene):
    collection = bpy.data.collections.get(COLLECTION_NAME)
    if collection is None:
        collection = bpy.data.collections.new(COLLECTION_NAME)
    if collection.name not in scene.collection.children:
        scene.collection.children.link(collection)
    # Re-running this module only replaces its own previous studio objects.
    for obj in list(collection.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    return collection


def _aim(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def _area_light(collection, name, location, target, energy, size, color,
                size_y=None):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.color = color
    data.shape = "RECTANGLE" if size_y is not None else "DISK"
    data.size = size
    if size_y is not None:
        data.size_y = size_y
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    obj.location = location
    _aim(obj, target)
    return obj


def _camera(collection, label, position, target, scale):
    data = bpy.data.cameras.new("GB_Camera_" + label)
    data.type = "ORTHO"
    data.ortho_scale = scale
    data.lens = 70
    data.clip_start = 0.05
    data.clip_end = 150.0
    data.dof.use_dof = False
    obj = bpy.data.objects.new("GB_Camera_" + label, data)
    collection.objects.link(obj)
    obj.location = position
    _aim(obj, target)
    return obj


def _floor(collection):
    material = bpy.data.materials.get("GB_Charcoal_Floor")
    if material is None:
        material = bpy.data.materials.new("GB_Charcoal_Floor")
    material.use_nodes = True
    material.diffuse_color = _hex_linear("#030504")
    shader = material.node_tree.nodes.get("Principled BSDF")
    if shader is not None:
        shader.inputs["Base Color"].default_value = _hex_linear("#030504")
        shader.inputs["Metallic"].default_value = 0.0
        shader.inputs["Roughness"].default_value = 0.84
        _set_input(shader, ("Specular IOR Level", "Specular"), 0.025)
    mesh = bpy.data.meshes.new("GB_Studio_Floor_Mesh")
    mesh.from_pydata(
        [(-100, -100, -0.004), (100, -100, -0.004),
         (100, 100, -0.004), (-100, 100, -0.004)],
        [], [(0, 1, 2, 3)],
    )
    mesh.update()
    floor = bpy.data.objects.new("GB_Studio_Charcoal_Floor", mesh)
    collection.objects.link(floor)
    floor.data.materials.append(material)
    return floor


def setup_studio(scene, out_dir):
    """Prepare a clean full-body render stage and return four camera objects.

    Returns ``{"Hero": ..., "Front": ..., "Side": ..., "Back": ...}``.
    The selected camera is Hero; callers can select a returned camera and set
    ``scene.render.filepath`` before their own ``bpy.ops.render.render`` call.
    ``out_dir`` is recorded but not created by this helper. The default output
    is ``hero.png``. Cycles CPU is deliberately the safe default; a caller may
    opt into an already-configured GPU without this module changing preferences.
    """
    collection = _collection(scene)
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = 0.025
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 8
    scene.cycles.diffuse_bounces = 4
    scene.cycles.glossy_bounces = 4
    scene.cycles.transparent_max_bounces = 8
    scene.cycles.sample_clamp_indirect = 5.0
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 1200
    scene.render.resolution_percentage = 100
    scene.render.pixel_aspect_x = 1.0
    scene.render.pixel_aspect_y = 1.0
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.color_depth = "8"
    scene.render.image_settings.compression = 20
    scene.render.film_transparent = False
    scene.render.use_file_extension = True
    scene.render.filepath = str(Path(out_dir) / "hero.png")
    scene.render.fps = 30

    # Standard preserves the saturated lime pigment. AgX's highlight gamut
    # compression made the first proof pale/yellow-white. Keep the illumination
    # and specular response restrained instead of relying on that compression.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = -0.45
    scene.view_settings.gamma = 1.0

    world = bpy.data.worlds.get("GB_Studio_World")
    if world is None:
        world = bpy.data.worlds.new("GB_Studio_World")
    world.use_nodes = True
    world.node_tree.nodes.clear()
    background = world.node_tree.nodes.new("ShaderNodeBackground")
    background.inputs["Color"].default_value = (0.24, 0.25, 0.245, 1.0)
    background.inputs["Strength"].default_value = 0.025
    world_output = world.node_tree.nodes.new("ShaderNodeOutputWorld")
    world.node_tree.links.new(background.outputs["Background"],
                               world_output.inputs["Surface"])
    scene.world = world
    _floor(collection)

    # A lower, more lateral key gives actual form shadows without a white cap
    # on the head. A weak broad fill keeps the axilla/knees readable; the strip
    # and back fill stay subordinate so they do not wash out the green pigment.
    _area_light(collection, "GB_Key_Softbox", (-4.3, -3.6, 2.9),
                (0, 0, 1.02), 410.0, 2.8, (1.0, 1.0, 0.98), 3.2)
    _area_light(collection, "GB_Fill_Softbox", (3.4, -2.4, 1.8),
                (0, 0, 0.9), 55.0, 3.0, (0.95, 0.985, 1.0), 3.0)
    _area_light(collection, "GB_Rim_Strip", (2.1, 2.3, 2.5),
                (0, 0, 1.05), 155.0, 1.0, (0.97, 1.0, 0.97), 3.1)
    _area_light(collection, "GB_Back_Soft_Fill", (-2.2, 3.5, 2.2),
                (0, 0, 1.0), 85.0, 3.3, (1.0, 1.0, 0.98), 3.0)

    cameras = {
        "Hero": _camera(collection, "Hero", (1.822, -6.8, 1.45),
                        (0, 0, 0.94), 2.20),
        "Front": _camera(collection, "Front", (0, -7.0, 0.94),
                         (0, 0, 0.94), 2.14),
        "Side": _camera(collection, "Side", (7.0, 0, 0.94),
                        (0, 0, 0.94), 2.14),
        "Back": _camera(collection, "Back", (0, 7.0, 0.94),
                        (0, 0, 0.94), 2.14),
    }
    scene.camera = cameras["Hero"]
    scene["GB_studio_note"] = "1.80 m character; Z up; face -Y; feet on Z=0"
    scene["GB_studio_output_directory"] = str(Path(out_dir))
    return cameras
