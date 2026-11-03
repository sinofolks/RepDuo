"""Reference-led v2 studio; model geometry and the v1 studio are untouched.

Import ``setup_studio_v2(scene, out_dir)`` for Hero/Front/Side/Back cameras, or
run in background Blender with a loaded v1 scene for an isolated CPU proof.
"""

import argparse
import hashlib
from pathlib import Path
import sys

import bpy

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import studio as legacy


def _material(name, color, roughness, specular):
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = legacy._hex_linear(color)
    material.node_tree.nodes.clear()
    shader = material.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Base Color"].default_value = legacy._hex_linear(color)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = 0.0
    shader.inputs["IOR"].default_value = 1.46
    legacy._set_input(shader, ("Specular IOR Level", "Specular"), specular)
    legacy._set_input(shader, ("Coat Weight", "Clearcoat"), 0.0)
    legacy._set_input(shader, ("Subsurface Weight", "Subsurface"), 0.0)
    output = material.node_tree.nodes.new("ShaderNodeOutputMaterial")
    material.node_tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    return material


def lime_material_v2():
    """Satin yellow-lime pigment with restrained neutral highlight response."""
    return _material("GB_V2_Satin_Lime", "#B8E53B", 0.48, 0.24)


def _light(name, location, target, watts, width, height, color=(1, 1, 1)):
    obj = bpy.data.objects[name]
    obj.location = location
    legacy._aim(obj, target)
    obj.data.energy = watts
    obj.data.size = width
    obj.data.size_y = height
    obj.data.color = color
    return obj


def setup_studio_v2(scene, out_dir, variant="Selected3"):
    """Return Hero/Front/Side/Back camera objects; do not render or save files.

    No Cycles device preferences are touched. Geometry, rig, poses, and object
    transforms outside the studio are preserved. GreenBody's material slots
    are set to the v2 satin pigment if the body exists in the loaded scene.
    """
    cameras = legacy.setup_studio(scene, out_dir)
    scene.cycles.device = "CPU"
    scene.cycles.samples = 64
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = -0.10
    scene.view_settings.gamma = 1.0
    background = next(node for node in scene.world.node_tree.nodes if node.type == "BACKGROUND")
    background.inputs["Color"].default_value = (0.24, 0.255, 0.25, 1.0)
    background.inputs["Strength"].default_value = 0.04

    # Camera is on negative X: the neutral reference shows the other ear and
    # the torso's shadow-side three-quarter plane, unlike the v1 camera.
    cameras["Hero"].location = (-2.00, -6.8, 1.45)
    legacy._aim(cameras["Hero"], (0, 0, 0.93))
    cameras["Hero"].data.ortho_scale = 2.17

    # A dominant upper-right/front key and a weaker upper-left/rear rim form
    # the broad muscle shadows in the reference; near-camera fill stays weak.
    _light("GB_Key_Softbox", (3.1, -3.2, 3.7), (0, 0, 1.1),
           920.0, 2.1, 2.9, (1.0, 1.0, 0.98))
    _light("GB_Fill_Softbox", (-2.8, -4.5, 1.7), (0, 0, 0.95),
           65.0, 3.0, 3.3, (0.98, 0.99, 1.0))
    _light("GB_Rim_Strip", (-2.6, 1.1, 3.6), (0, 0, 1.05),
           450.0, 1.35, 3.2, (1.0, 1.0, 0.98))
    _light("GB_Back_Soft_Fill", (2.2, 3.5, 2.6), (0, 0, 1.05),
           130.0, 3.0, 3.3, (0.98, 1.0, 1.0))

    material = _material("GB_V2_Satin_Lime_AgX", "#B7ED17", 0.43, 0.30)
    if variant in {"B", "Selected", "Selected2", "Selected3"}:
        # Alternate proof keeps the directional light but uses a less intense
        # color transform/pigment combination for comparison, not a fake score.
        scene.view_settings.view_transform = "Standard"
        scene.view_settings.look = "None"
        scene.view_settings.exposure = -1.0
        material = lime_material_v2()
    if variant in {"Selected", "Selected2", "Selected3"}:
        # The two actual proofs rejected AgX's whitening. B retained the right
        # hue but had a white-light reflection pool. This restrained correction
        # is intended for the caller's next combined-geometry review render.
        scene.view_settings.exposure = -1.35
        for name, contribution in (("GB_Key_Softbox", 0.10),
                                    ("GB_Fill_Softbox", 0.0),
                                    ("GB_Rim_Strip", 0.15),
                                    ("GB_Back_Soft_Fill", 0.10)):
            bpy.data.objects[name].data.specular_factor = contribution
    if variant in {"Selected2", "Selected3"}:
        # Cycles' actual proof retained a grey softbox reflection despite the
        # specular factors. Hide only the emitters from glossy rays: the floor
        # still reflects the illuminated green body, but no white softbox pool.
        # This is a standard studio reflection-control flag, not a fake overlay.
        scene.view_settings.exposure = -2.0
        background.inputs["Strength"].default_value = 0.025
        bpy.data.objects["GB_Fill_Softbox"].data.energy = 45.0
        for name in ("GB_Key_Softbox", "GB_Fill_Softbox", "GB_Rim_Strip", "GB_Back_Soft_Fill"):
            bpy.data.objects[name].visible_glossy = False
    body = bpy.data.objects.get("GreenBody")
    if body is not None and body.type == "MESH":
        body.data.materials.clear()
        body.data.materials.append(material)
    if variant == "Selected3":
        # Cycles light linking keeps the lamp's satin response on GreenBody,
        # but excludes direct lamp response on the ground. Green-body bounce
        # and reflection remain real indirect paths rather than an overlay.
        if body is None or body.type != "MESH":
            raise RuntimeError("Selected3 requires the GreenBody mesh for receiver linking.")
        receiver_name = "GB_V2_CharacterLightReceivers"
        receivers = bpy.data.collections.get(receiver_name) or bpy.data.collections.new(receiver_name)
        if body.name not in receivers.objects:
            receivers.objects.link(body)
        for relation in receivers.collection_objects:
            relation.light_linking.link_state = "INCLUDE"
        scene.view_settings.exposure = -1.65
        for name in ("GB_Key_Softbox", "GB_Fill_Softbox", "GB_Rim_Strip", "GB_Back_Soft_Fill"):
            lamp = bpy.data.objects[name]
            lamp.visible_glossy = True
            lamp.data.specular_factor = 1.0
            lamp.light_linking.receiver_collection = receivers

    floor = bpy.data.objects["GB_Studio_Charcoal_Floor"]
    floor.data.materials.clear()
    floor.data.materials.append(_material("GB_V2_Polished_Charcoal", "#070907",
                                          0.39 if variant in {"Selected", "Selected2", "Selected3"} else 0.34,
                                          0.24 if variant in {"Selected2", "Selected3"} else (
                                              0.30 if variant == "Selected" else 0.42)))
    scene["GB_v2_studio_variant"] = variant
    scene["GB_v2_studio_note"] = "Reference neutral matching: negative-X camera, directional satin key, restrained floor reflection"
    return cameras


def _geometry_fingerprint(body):
    data = [tuple(vertex.co) for vertex in body.data.vertices]
    data.extend(tuple(face.vertices) for face in body.data.polygons)
    data.append(tuple(value for row in body.matrix_world for value in row))
    return hashlib.sha256(repr(data).encode()).hexdigest()


def main():
    if not bpy.app.background:
        raise RuntimeError("Use background Blender; do not overwrite the user's GUI scene.")
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", choices=("A", "B", "Selected", "Selected2", "Selected3"), default="Selected3")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    out_dir = ROOT / "renders" / "v2-experiments"
    out_dir.mkdir(parents=True, exist_ok=True)
    body = bpy.data.objects["GreenBody"]
    before = _geometry_fingerprint(body)
    setup_studio_v2(bpy.context.scene, out_dir, args.variant)
    assert before == _geometry_fingerprint(body), "Geometry or body transform changed"
    scene = bpy.context.scene
    scene.cycles.samples = 24
    scene.render.resolution_x = 600
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.filepath = str(out_dir / ("studio-" + args.variant.lower() + ".png"))
    bpy.ops.wm.save_as_mainfile(filepath=str(out_dir / ("studio-" + args.variant.lower() + ".blend")))
    bpy.ops.render.render(write_still=True)
    print("STUDIO_V2_PROOF", scene.render.filepath, flush=True)


if __name__ == "__main__":
    main()
