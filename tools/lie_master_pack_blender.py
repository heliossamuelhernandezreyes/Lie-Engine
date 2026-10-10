"""Pack real unlit/normal/depth captures into ONE reusable object-local master.

Run in Blender after lie_capture_surface_blender.py. Each source camera supplies
one normal map; no lighting-angle permutations. Closed-cylinder lab contract.
"""
import hashlib
import json
import math
import struct
import sys
from pathlib import Path
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).parent))
from lie_rigid_master import cylinder_patches, patch_id


def lie(p):
    return Vector((p.x, p.z, -p.y))


def pack(root):
    manifest = json.loads((root/"manifest.json").read_text())
    if manifest["schema_version"] != 2 or manifest["resolution"] != [128, 128]:
        raise ValueError("LIE-14 master requires schema-2 128-square capture channels")
    near, far = (manifest["linear_depth_meters"][k] for k in ["near", "far"])
    center = Vector(manifest["center_blender"])
    radius, half = .18, .6
    points, views, probes = [], [], []
    rejected = 0
    for view_id, item in enumerate(manifest["views"]):
        channels = {}
        for key in ["albedo", "normal", "depth"]:
            image = bpy.data.images.load(str((root/item["channels"][key]).resolve()), check_existing=False)
            image.colorspace_settings.name = "Non-Color"
            channels[key] = list(image.pixels[:])
            bpy.data.images.remove(image)
        matrix = Matrix(item["camera_matrix_blender"])
        origin = lie(matrix.translation-center)
        right, up, forward = lie(matrix.col[0].xyz), lie(matrix.col[1].xyz), -lie(matrix.col[2].xyz)
        start = len(points)
        scale = manifest["orthographic_scale"]
        for y in range(128):
            for x in range(128):
                pixel = ((127-y)*128+x)*4
                rgba = channels["albedo"][pixel:pixel+4]
                z = channels["depth"][pixel]
                n = lie(Vector([v*2-1 for v in channels["normal"][pixel:pixel+3]])).normalized()
                if rgba[3] < .99 or n.length_squared < .5 or not 0 <= z <= 1:
                    continue
                p = origin+((x+.5)/128-.5)*scale*right+(.5-(y+.5)/128)*scale*up+(near+z*(far-near))*forward
                distance = abs(abs(p.y)-half) if abs(n.y) > .8 else abs(math.hypot(p.x, p.z)-radius)
                if distance > .006 or abs(p.y) > half+.006:
                    rejected += 1
                    continue
                gray = max(rgba[:3])
                if max(rgba[:3])-min(rgba[:3]) > .001:
                    raise ValueError("Master must be neutral grayscale")
                points.append([*p, gray, *n, float(patch_id(p, n))])
        direction = origin.normalized()
        views.append({"start": start, "count": len(points)-start, "direction": list(direction),
                      "azimuth": item["azimuth_degrees"], "elevation": item["elevation_degrees"]})
    if len(views) != 36 or len(points) < 10000:
        raise ValueError("Expected 36 camera views and sufficient captured samples")
    # Actual captured samples within ONE coarse node, with distinct normals.
    for a, first in enumerate(points):
        if abs(first[1]) < .08 or first[7] >= 16:
            continue
        for b in range(a+1, min(a+1800, len(points))):
            second = points[b]
            ndot = sum(first[k]*second[k] for k in range(4, 7))
            if first[7] == second[7] and ndot < .9 and abs(first[1]-second[1]) < .1:
                probes = [a, b]
                break
        if probes:
            break
    if not probes:
        raise ValueError("Could not find captured within-node normal probes")
    patches = cylinder_patches()
    for i, patch in enumerate(patches):
        values = [p[3] for p in points if int(p[7]) == i]
        patch["gray_mean"] = sum(values)/len(values) if values else .8
    data = b"".join(struct.pack("<8f", *p) for p in points)
    (root/"master-samples.bin").write_bytes(data)
    result = {"schema": 1, "master_id": "cylinder-neutral-v1", "sample_count": len(points),
              "sample_stride_bytes": 32, "views": views, "patches": patches,
              "bounds": [[-.18, -.6, -.18], [.18, .6, .18]],
              "collision": {"kind": "cylinder", "radius": radius, "half_height": half},
              "probe_samples": probes, "rejected_boundary_pixels": rejected,
              "normal_space": "object-local Lie XYZ", "neutral_lighting": True,
              "capture_light_variants_per_view": 0,
              "normal_maps_per_view": 1, "source_channels_per_view": 3,
              "sample_sha256": hashlib.sha256(data).hexdigest()}
    (root/"master.json").write_text(json.dumps(result, indent=2)+"\n")
    print("LIE-14 MASTER PACK", len(views), "views", len(points), "shared samples", "one normal map per view")


if __name__ == "__main__":
    pack(Path(sys.argv[sys.argv.index("--")+1]).resolve())
