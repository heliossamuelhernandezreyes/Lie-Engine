extends RefCounted
## LIE-03 — reconstruct a camera-captured orthographic depth surface into a
## bounded, view-dependent triangle mesh. This is NOT the original source mesh.
## The GPU's regular Z buffer now handles depth tests between different nodes.
##
## Node origin = Blender capture orbit center. Coordinate conventions:
## Lie Y-up/+Z-front, captured camera at direction * (4.5 * capture radius).
## A depth PNG stores positive camera-axis meters mapped to near..far.
## UV coordinates point to the same pixel in color, normal and depth textures.
const ViewIndex = preload("res://scripts/lie_view_index.gd")

static func default_capture() -> Dictionary:
    return {"radius": 0.85, "orthographic_scale": 2.295,
        "near": 2.72, "far": 4.93, "capture_distance": 3.825}

static func capture_from_manifest(manifest: Dictionary) -> Dictionary:
    if int(manifest.get("schema_version", 0)) != 2 or str(manifest.get("projection", "")) != "orthographic":
        return {}
    var radius := float(manifest.get("radius", 0))
    var scale := float(manifest.get("orthographic_scale", 0))
    var ranges: Dictionary = manifest.get("linear_depth_meters", {})
    var near := float(ranges.get("near", 0))
    var far := float(ranges.get("far", 0))
    if radius <= 0.0 or scale <= 0.0 or near <= 0.0 or far <= near:
        return {}
    return {"radius": radius, "orthographic_scale": scale,
        "near": near, "far": far, "capture_distance": radius * 4.5}


static func pixel_position(u: float, v: float, depth_value: float,
        capture: Dictionary, az: int, az_steps: int, elevation: float) -> Vector3:
    var direction: Vector3 = ViewIndex.direction_for_view(az, az_steps, elevation)
    # Camera looks towards -direction, local camera +Z is +direction.
    var basis: Basis = Basis.looking_at(-direction, Vector3.UP)
    var right: Vector3 = basis.x
    var up: Vector3 = basis.y
    var extent: float = float(capture["orthographic_scale"])
    var meters: float = lerpf(float(capture["near"]), float(capture["far"]),
        clampf(depth_value, 0.0, 1.0))
    return (direction * float(capture["capture_distance"])
        + right * ((u - 0.5) * extent)
        + up * ((0.5 - v) * extent)
        - direction * meters)


static func build_mesh(albedo: Image, depth: Image, capture: Dictionary,
        az: int, az_steps: int, elevation: float, stride: int = 2,
        discontinuity_meters: float = 0.30) -> Dictionary:
    if albedo == null or depth == null or albedo.is_empty() or depth.is_empty():
        return {"mesh": null, "vertices": 0, "triangles": 0}
    var width := albedo.get_width()
    var height := albedo.get_height()
    if width != depth.get_width() or height != depth.get_height() or width < 2 or height < 2:
        return {"mesh": null, "vertices": 0, "triangles": 0}
    stride = maxi(stride, 1)
    # Max grid is bounded; 2K capture does not imply 4 million vertices.
    stride = maxi(stride, ceili(sqrt(float(width * height) / 65536.0)))
    var grid_width := ceili(float(width - 1) / float(stride)) + 1
    var grid_height := ceili(float(height - 1) / float(stride)) + 1
    var verts := PackedVector3Array()
    var uv := PackedVector2Array()
    var depth_meters := PackedFloat32Array()
    var valid := PackedByteArray()
    var range_meters: float = float(capture["far"]) - float(capture["near"])
    for gy in range(grid_height):
        var y := mini(gy * stride, height - 1)
        for gx in range(grid_width):
            var x := mini(gx * stride, width - 1)
            var u := (float(x) + 0.5) / float(width)
            var v := (float(y) + 0.5) / float(height)
            var c := albedo.get_pixel(x, y)
            var z := depth.get_pixel(x, y).r
            var is_valid := c.a >= 0.5 and is_finite(z)
            verts.append(pixel_position(u, v, z, capture, az, az_steps, elevation))
            uv.append(Vector2(u, v))
            depth_meters.append(z * range_meters)
            valid.append(1 if is_valid else 0)

    var indices := PackedInt32Array()
    var triangles := 0
    for gy in range(grid_height - 1):
        for gx in range(grid_width - 1):
            var a := gy * grid_width + gx
            var b := a + 1
            var c := a + grid_width
            var d := c + 1
            for tri in [[a, c, b], [b, c, d]]:
                if valid[tri[0]] == 0 or valid[tri[1]] == 0 or valid[tri[2]] == 0:
                    continue
                var low := minf(depth_meters[tri[0]], minf(depth_meters[tri[1]], depth_meters[tri[2]]))
                var high := maxf(depth_meters[tri[0]], maxf(depth_meters[tri[1]], depth_meters[tri[2]]))
                if high - low > discontinuity_meters:
                    continue
                indices.append_array(PackedInt32Array(tri))
                triangles += 1
    if indices.is_empty():
        return {"mesh": null, "vertices": verts.size(), "triangles": 0}
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = verts
    arrays[Mesh.ARRAY_TEX_UV] = uv
    arrays[Mesh.ARRAY_INDEX] = indices
    var result := ArrayMesh.new()
    result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return {"mesh": result, "vertices": verts.size(), "triangles": triangles}
