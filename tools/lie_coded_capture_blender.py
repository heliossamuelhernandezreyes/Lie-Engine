"""Offline grayscale + pixel material + stable XYZ patch association.

Only constant opaque Principled base colors are accepted for patch transport.
The rendered unlit pixels remain separate grayscale and RGB material values.
Original triangle geometry is exported solely as an invisible lighting proxy.
"""
import json
import math
import struct
from collections import defaultdict

def export_codes(meshes, original_materials, manifest, root):
    import bpy
    from mathutils import Vector, Matrix
    from mathutils.bvhtree import BVHTree
    center = Vector(manifest["center_blender"])
    def lie(v):
        return Vector((v.x, v.z, -v.y))
    materials, triangles, groups, triangle_keys = {}, [], defaultdict(list), []
    for obj in meshes:
        mesh = obj.data
        mesh.calc_loop_triangles()
        for tri in mesh.loop_triangles:
            source = original_materials[obj.name][tri.material_index]
            principled = next((n for n in source.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if principled is None or principled.inputs["Base Color"].is_linked:
                raise ValueError("LIE-12 patch exporter requires constant Principled base colors: " + source.name)
            base = list(principled.inputs["Base Color"].default_value)[:3]
            gray = max(base)
            tint = [v/gray if gray > 1e-9 else 0 for v in base]
            absorption = int(source.get("lie_absorption_code", 150 if "bounce red" in source.name else 200))
            material = source.name
            materials[material] = {"absorption_code": absorption, "tint_linear": tint}
            vertices = [lie(obj.matrix_world @ mesh.vertices[i].co - center) for i in tri.vertices]
            normal = (vertices[1]-vertices[0]).cross(vertices[2]-vertices[0])
            area = normal.length*.5
            if area < 1e-10:
                continue
            normal.normalize()
            centroid = sum(vertices, Vector())/3
            # Fixed 0.38 m spatial bins + dominant normal + material. Stable IDs
            # are built once, never selected according to the target camera.
            axis = max(range(3), key=lambda i: abs(normal[i]))
            key = (material, *(math.floor(x/.38) for x in centroid), axis, normal[axis] > 0)
            index = len(triangles)
            triangles.append([list(v) for v in vertices])
            triangle_keys.append(key)
            groups[key].append((index, centroid, normal, area, gray))
    if len(triangles) > 16384:
        raise ValueError("LIE-12 triangle budget exceeded")
    verts = [Vector(v) for tri in triangles for v in tri]
    bvh = BVHTree.FromPolygons(verts, [(i*3, i*3+1, i*3+2) for i in range(len(triangles))], all_triangles=True)
    patches, ids = [], {}
    for key, values in groups.items():
        area = sum(v[3] for v in values)
        average = sum((v[1]*v[3] for v in values), Vector())/area
        # Choose an actual triangle centroid, so coarse cluster centers do not
        # float inside the source geometry and falsely shadow themselves.
        representative = min(values, key=lambda v: (v[1]-average).length_squared)
        normal = sum((v[2]*v[3] for v in values), Vector()).normalized()
        ids[key] = len(patches)
        patches.append({"position": list(representative[1]), "normal": list(normal),
                        "area": area, "gray_mean": sum(v[4]*v[3] for v in values)/area,
                        "material": key[0], "surface": "red" if "bounce red" in key[0] else "capture"})
    if len(patches) > 1024:
        raise ValueError("LIE-12 node budget exceeded: " + str(len(patches)))
    count = len(patches)
    visible = [0]*(count*count)
    for i, a in enumerate(patches):
        for j in range(i+1, count):
            start, end = Vector(a["position"]), Vector(patches[j]["position"])
            delta = end-start
            if delta.length < 1e-8:
                continue
            hit = bvh.ray_cast(start+delta*.001, delta.normalized(), delta.length*.998)[0]
            visible[i*count+j] = visible[j*count+i] = int(hit is None)
    model = {"schema": 1, "bounces": 2, "patches": patches, "materials": materials,
             "triangles": triangles, "mesh_visibility": visible, "blockers": [],
             "lights": [{"position": [-.65, .45, .35], "radius": 6, "power_rgb": [35, 35, 35]}]}
    (root/"light-model.json").write_text(json.dumps(model, separators=(",", ":"), allow_nan=False)+"\n")
    selected = [v for v in manifest["views"] if abs(v["elevation_degrees"]-20) < .01]
    if len(selected) != 4 or manifest["resolution"] != [128, 128]:
        raise ValueError("LIE-12 v1 requires four 128-square captures at elevation 20 degrees")
    codes, samples, sources = bytearray(), bytearray(), []
    mapped, max_distance, max_raw_distance, rejected, candidates = 0, 0, 0, 0, 0
    for item in selected:
        def pixels(channel):
            image = bpy.data.images.load(str((root/item["channels"][channel]).resolve()), check_existing=False)
            image.colorspace_settings.name = "Non-Color"
            values = list(image.pixels[:])
            bpy.data.images.remove(image)
            return values
        rgba, depth, normals = pixels("albedo"), pixels("depth"), pixels("normal")
        matrix = Matrix(item["camera_matrix_blender"])
        origin = lie(matrix.translation-center)
        right, up, forward = lie(matrix.col[0].xyz), lie(matrix.col[1].xyz), -lie(matrix.col[2].xyz)
        sources.append({"origin": list(origin), "right": list(right), "up": list(up), "forward": list(forward)})
        for y in range(128):
            for x in range(128):
                # Blender Image pixels are bottom-up; runtime source UVs are top-down.
                index = ((127-y)*128+x)*4
                c, z, encoded = rgba[index:index+4], depth[index], normals[index:index+3]
                n = lie(Vector([v*2-1 for v in encoded])).normalized()
                valid = c[3] >= .5 and n.length_squared > .01 and 0 <= z <= 1
                point = origin + ((x+.5)/128-.5)*manifest["orthographic_scale"]*right + (.5-(y+.5)/128)*manifest["orthographic_scale"]*up + (manifest["linear_depth_meters"]["near"]+z*(manifest["linear_depth_meters"]["far"]-manifest["linear_depth_meters"]["near"]))*forward
                node = -1
                if valid:
                    candidates += 1
                    nearest = bvh.find_nearest(point)
                    if nearest[2] is None:
                        raise ValueError("Capture pixel has no source proxy association")
                    max_raw_distance = max(max_raw_distance, nearest[3])
                    # Multisample boundaries can mix two valid depths into a
                    # point between surfaces. Never label that fictitious point.
                    if nearest[3] > manifest["radius"]*.02:
                        rejected += 1
                        valid = False
                    else:
                        node = ids[triangle_keys[nearest[2]]]
                        max_distance = max(max_distance, nearest[3])
                        mapped += 1
                gray = max(c[:3]) if valid else 0
                tint = [v/gray if gray > 1e-9 else 0 for v in c[:3]]
                # Two vec4: grayscale neutral RGB + validity; RGB material filter + node ID.
                codes.extend(struct.pack("<8f", gray, gray, gray, float(valid), *tint, node))
                samples.extend(struct.pack("<8f", (x+.5)/128, (y+.5)/128, z, float(valid), *n, 0))
    if candidates == 0 or rejected/candidates > .05:
        raise ValueError("Too many geometrically ambiguous capture pixels: " + str(rejected) + "/" + str(candidates))
    (root/"pixel-codes.bin").write_bytes(codes)
    (root/"sample-normal.bin").write_bytes(samples)
    metadata = {"schema": 1, "sources": sources, "sample_count": 4*128*128,
                "mapped_valid_pixels": mapped, "patch_count": count, "triangle_count": len(triangles),
                "rejected_mixed_depth_pixels": rejected, "candidate_valid_pixels": candidates,
                "rejected_mixed_depth_fraction": rejected/max(candidates, 1), "max_raw_depth_proxy_distance": max_raw_distance,
                "max_depth_proxy_distance": max_distance, "capture_radius": manifest["radius"],
                "ortho_scale": manifest["orthographic_scale"], "near": manifest["linear_depth_meters"]["near"],
                "far": manifest["linear_depth_meters"]["far"], "camera_elevation": 20,
                "limitations": "Constant opaque Principled colors; finite clustered diffuse patches; source triangles are invisible visibility data."}
    (root/"code-manifest.json").write_text(json.dumps(metadata, indent=2)+"\n")
    print("LIE-12 CODED CAPTURE PASS", json.dumps(metadata))
