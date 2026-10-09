"""LIE-02: three real orthographic capture channels per angle.

Blender 4.x: --input asset.glb --out assets/captures/demo_shard
RGBA Albedo (unlit Principled base color), Blender-world Normal, normalized
camera-axis Depth. PNGs are independent of the original object's mesh at runtime.
First experiment only supports OPAQUE Principled glTF materials; alpha blend and
full PBR are intentionally not claimed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lie_angles import capture_direction, lie_to_blender, view_code


def arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--azimuth-steps", default=16, type=int)
    parser.add_argument("--elevations", default="-30,0,30")
    parser.add_argument("--resolution", default=256, type=int)
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parser.parse_args(argv)
    args.angles = [float(v) for v in args.elevations.split(",")]
    if not args.input.is_file() or args.input.suffix.lower() not in (".glb", ".gltf"):
        parser.error("--input must be an existing glTF or GLB")
    if args.azimuth_steps < 4 or not args.angles or any(abs(a) >= 90 for a in args.angles):
        parser.error("At least 4 azimuth samples, elevations between -90 and 90")
    if args.resolution not in (128, 256, 512, 1024, 2048):
        parser.error("Unsupported power-of-two resolution")
    return args


def render_material_pass(scene, path: Path, depth: int):
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = str(depth)
    scene.render.filepath = str(path.resolve())
    scene.camera.data.lens = 50
    import bpy
    bpy.ops.render.render(write_still=True)
    if not path.is_file() or path.stat().st_size < 100:
        raise RuntimeError("Missing output " + str(path))


def flat_albedo_material(source):
    """Copy material node graph, replace surface output with emission of Base Color."""
    import bpy
    mat = source.copy()
    mat.name = "LieUnlit | " + source.name
    if not mat.use_nodes:
        return mat
    nt = mat.node_tree
    output = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None)
    principled = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if output is None or principled is None:
        # Unsupported material systems remain conspicuous magenta in base pass.
        nt.nodes.clear()
        output = nt.nodes.new("ShaderNodeOutputMaterial")
        emission = nt.nodes.new("ShaderNodeEmission")
        emission.inputs["Color"].default_value = (1, 0, 1, 1)
        nt.links.new(emission.outputs["Emission"], output.inputs["Surface"])
        return mat
    color = principled.inputs["Base Color"]
    emission = nt.nodes.new("ShaderNodeEmission")
    emission.inputs["Strength"].default_value = 1.0
    if color.is_linked:
        nt.links.new(color.links[0].from_socket, emission.inputs["Color"])
    else:
        emission.inputs["Color"].default_value = color.default_value
    nt.links.new(emission.outputs["Emission"], output.inputs["Surface"])
    return mat


def normal_material():
    """Encode Blender-world normalized N [-1,+1] to RGB [0,1]."""
    import bpy
    m = bpy.data.materials.new("Lie | normal world axes")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    geometry = nt.nodes.new("ShaderNodeNewGeometry")
    scale = nt.nodes.new("ShaderNodeVectorMath")
    scale.operation = "MULTIPLY"
    scale.inputs[1].default_value = (0.5, 0.5, 0.5)
    offset = nt.nodes.new("ShaderNodeVectorMath")
    offset.operation = "ADD"
    offset.inputs[1].default_value = (0.5, 0.5, 0.5)
    emission = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(geometry.outputs["Normal"], scale.inputs[0])
    nt.links.new(scale.outputs["Vector"], offset.inputs[0])
    nt.links.new(offset.outputs["Vector"], emission.inputs["Color"])
    nt.links.new(emission.outputs["Emission"], out.inputs["Surface"])
    return m


def depth_material(near: float, far: float):
    """Encode positive orthographic camera-axis depth, normalized to [0,1]."""
    import bpy
    m = bpy.data.materials.new("Lie | camera linear depth")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    geom = nt.nodes.new("ShaderNodeNewGeometry")
    sub = nt.nodes.new("ShaderNodeVectorMath")
    sub.operation = "SUBTRACT"
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    scale = nt.nodes.new("ShaderNodeMapRange")
    scale.inputs["From Min"].default_value = near
    scale.inputs["From Max"].default_value = far
    scale.inputs["To Min"].default_value = 0.0
    scale.inputs["To Max"].default_value = 1.0
    scale.clamp = True
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(geom.outputs["Position"], sub.inputs[0])
    nt.links.new(sub.outputs["Vector"], dot.inputs[0])
    nt.links.new(dot.outputs["Value"], scale.inputs["Value"])
    nt.links.new(scale.outputs["Result"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    return m, sub.inputs[1], dot.inputs[1]


def main():
    import bpy
    from mathutils import Vector

    args = arguments()
    args.out.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(args.input.resolve()))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise RuntimeError("Model contains no mesh")
    original_materials = {o.name: [s.material for s in o.material_slots] for o in meshes}
    if any(m is None for slots in original_materials.values() for m in slots):
        raise RuntimeError("Lie-02 requires all mesh material slots assigned")
    # World-space fixed capture bounds, not recalculated per view.
    points = [o.matrix_world @ Vector(corner) for o in meshes for corner in o.bound_box]
    lo = Vector([min(p[i] for p in points) for i in range(3)])
    hi = Vector([max(p[i] for p in points) for i in range(3)])
    center = (lo + hi) * 0.5
    radius = max((hi - lo).length * 0.5, 0.05)
    near = radius * 3.2
    far = radius * 5.8

    scene = bpy.context.scene
    # Unlit outputs: no lights or scene shadow effects are intentionally baked.
    scene.render.engine = "BLENDER_EEVEE_NEXT" if bpy.app.version >= (4, 2, 0) else "BLENDER_EEVEE"
    scene.render.resolution_x = args.resolution
    scene.render.resolution_y = args.resolution
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Raw"
    scene.render.image_settings.file_format = "PNG"
    cam_data = bpy.data.cameras.new("LieCamera")
    cam = bpy.data.objects.new("LieCamera", cam_data)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = radius * 2.7

    replacements = {}
    for o in meshes:
        for s in o.material_slots:
            if s.material not in replacements:
                replacements[s.material] = flat_albedo_material(s.material)
            s.material = replacements[s.material]
    nmat = normal_material()
    dmat, camera_origin, camera_direction = depth_material(near, far)

    items = []
    for el_id, elevation in enumerate(args.angles):
        for az_id in range(args.azimuth_steps):
            direction = Vector(lie_to_blender(capture_direction(az_id, args.azimuth_steps, elevation)))
            cam.location = center + direction * radius * 4.5
            cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
            camera_origin.default_value = tuple(cam.location)
            camera_direction.default_value = tuple((center - cam.location).normalized())
            code = view_code(az_id, el_id)
            sha = {}
            for channel, mat, bits in (
                ("albedo", None, 8), ("normal", nmat, 16), ("depth", dmat, 16)
            ):
                scene.view_layers[0].material_override = mat
                path = args.out / (code + "." + channel + ".png")
                render_material_pass(scene, path, bits)
                sha[channel] = hashlib.sha256(path.read_bytes()).hexdigest()
            items.append({
                "code": code, "azimuth_index": az_id, "elevation_index": el_id,
                "azimuth_degrees": az_id * 360.0 / args.azimuth_steps,
                "elevation_degrees": elevation,
                "camera_position_blender": list(cam.location),
                "camera_matrix_blender": [list(row) for row in cam.matrix_world],
                "channels": {k: code + "." + k + ".png" for k in sha},
                "sha256": sha,
            })
    scene.view_layers[0].material_override = None
    output = {
        "schema_version": 2,
        "generator": "Lie Engine surface capture 0.2",
        "input_name": args.input.name,
        "input_sha256": hashlib.sha256(args.input.read_bytes()).hexdigest(),
        "blender_version": bpy.app.version_string,
        "asset_frame": "glTF +Y up, +Z front",
        "capture_frame": "Blender +Z up",
        "projection": "orthographic",
        "radius": radius,
        "center_blender": list(center),
        "orthographic_scale": cam_data.ortho_scale,
        "linear_depth_meters": {"near": near, "far": far},
        "normal_encoding": "world-blender XYZ mapped from [-1,+1] to [0,1]",
        "color_encoding": "unlit Principled base color; other graphs magenta fallback",
        "channels": ["albedo", "normal", "depth"],
        "alpha_limitations": "opaque glTF materials supported; semitransparency not guaranteed",
        "resolution": [args.resolution, args.resolution],
        "azimuth_steps": args.azimuth_steps,
        "elevation_degrees": args.angles,
        "views": items,
    }
    (args.out / "manifest.json").write_text(
        json.dumps(output, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(f"LIE-02 BLENDER CAPTURE PASS views={len(items)} channels=3 resolution={args.resolution}")


if __name__ == "__main__":
    main()
