"""Lie-01 PNG angular capture pipeline.

Usage (Blender 4.x):
blender --background --python tools/lie_capture_blender.py -- \
    --input /absolute/model.glb --out assets/captures/demo_shard \
    --azimuth-steps 16 --elevations=-30,0,30 --resolution 512

This is an RGB+alpha, light-baked *experimental* capture. Per-pixel normal,
depth and unlit albedo will be introduced in later gates. Do not use the
generated images as evidence of physically correct relighting.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lie_angles import capture_direction, lie_to_blender, view_code


def cli() -> argparse.Namespace:
    raw = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Generate deterministic Lie angular PNGs from glTF/GLB")
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--azimuth-steps", type=int, default=16)
    parser.add_argument("--elevations", default="-30,0,30")
    parser.add_argument("--resolution", type=int, default=512)
    args = parser.parse_args(raw)
    args.elevation_list = [float(x) for x in args.elevations.split(",")]
    if args.azimuth_steps < 4 or not args.elevation_list:
        parser.error("Need >= 4 azimuth steps and at least one elevation")
    if args.resolution not in (128, 256, 512, 1024, 2048):
        parser.error("Resolution must be 128, 256, 512, 1024, or 2048")
    if any(abs(x) >= 90 for x in args.elevation_list):
        parser.error("Elevations must be between -90 and +90 exclusive")
    if not args.input.is_file() or args.input.suffix.lower() not in (".glb", ".gltf"):
        parser.error("--input must point to an existing .glb or .gltf")
    return args


def main() -> None:
    import bpy
    from mathutils import Vector

    args = cli()
    args.out.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(args.input.resolve()))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("Source glTF contains no meshes")

    # World-space bounds of ALL mesh pieces: every view uses the same framing.
    coords = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    low = Vector([min(p[k] for p in coords) for k in range(3)])
    high = Vector([max(p[k] for p in coords) for k in range(3)])
    center = (low + high) / 2
    radius = max((high - low).length * 0.5, 0.01)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = args.resolution
    scene.render.resolution_y = args.resolution
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"

    camera_data = bpy.data.cameras.new("LieCaptureCamera")
    camera = bpy.data.objects.new("LieCaptureCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = radius * 2.7

    # Temporary static area light; lighting is intentionally baked at this phase.
    light_data = bpy.data.lights.new("LieCaptureKeyLight", "AREA")
    light = bpy.data.objects.new("LieCaptureKeyLight", light_data)
    bpy.context.collection.objects.link(light)
    light.location = center + Vector((-radius * 2.0, radius * 3.0, radius * 2.0))
    light_data.energy = 900.0
    light_data.shape = "DISK"
    light_data.size = radius * 3.0

    items = []
    for ei, elevation in enumerate(args.elevation_list):
        for ai in range(args.azimuth_steps):
            direction = Vector(lie_to_blender(capture_direction(ai, args.azimuth_steps, elevation)))
            camera.location = center + direction * (radius * 4.5)
            camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
            label = view_code(ai, ei)
            filename = label + ".png"
            scene.render.filepath = str((args.out / filename).resolve())
            bpy.ops.render.render(write_still=True)
            items.append({
                "code": label,
                "azimuth_index": ai,
                "elevation_index": ei,
                "azimuth_degrees": 360.0 * ai / args.azimuth_steps,
                "elevation_degrees": elevation,
                "image": filename,
            })

    source_hash = hashlib.sha256(args.input.read_bytes()).hexdigest()
    manifest = {
        "schema_version": 1,
        "generator": "Lie-01 Blender RGBA capture",
        "coordinate_convention": "+Z front, +X right, +Y up",
        "projection": "orthographic",
        "lighting": "baked; not physically relightable",
        "channels": ["RGBA"],
        "input_name": args.input.name,
        "input_sha256": source_hash,
        "blender_version": bpy.app.version_string,
        "azimuth_steps": args.azimuth_steps,
        "elevation_degrees": args.elevation_list,
        "resolution": [args.resolution, args.resolution],
        "views": items,
    }
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"LIE-01 CAPTURE: generated {len(items)} PNGs at {args.out.resolve()}")


if __name__ == "__main__":
    main()
