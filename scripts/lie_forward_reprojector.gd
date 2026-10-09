extends RefCounted
## LIE-05 EXPERIMENTAL: CPU forward reprojection of TWO captured depth images
## to the current perspective camera. Images are NOT source polygon geometry.
##
## Output: a single target-camera triangulated point surface. Each source
## pixel reconstructs a WORLD 3D point, then projects into target-camera screen
## coordinates and participates in a per-cell depth test. Disoccluded cells
## from the second view may fill gaps from the first. The output vertices are
## still actual 3D positions, so standard Godot Z-buffer remains functional.
##
## Slow CPU research reference: NOT optimized for 60 fps / Android.
const Mesher = preload("res://scripts/lie_depth_mesher.gd")

static func reconstruct(
        sources: Array, camera: Camera3D, node_world: Transform3D,
        capture: Dictionary, azimuth_steps: int,
        output_resolution: int = 128, crop_screen_pixels: float = 340.0,
        input_stride: int = 2,
        merge_depth_meters: float = 0.07,
        triangle_depth_meters: float = 0.32) -> Dictionary:
    if camera == null or sources.is_empty() or output_resolution < 16 or output_resolution > 256:
        return {"mesh": null, "triangles": 0, "coverage": 0,
            "source_hits": [], "accepted": 0}
    if crop_screen_pixels <= 1.0 or input_stride <= 0:
        return {"mesh": null, "triangles": 0, "coverage": 0,
            "source_hits": [], "accepted": 0}
    var size: int = output_resolution
    var count: int = size * size
    var z_buffer := PackedFloat32Array()
    var weighted_r := PackedFloat32Array()
    var weighted_g := PackedFloat32Array()
    var weighted_b := PackedFloat32Array()
    var weighted_position := PackedVector3Array()
    var weights := PackedFloat32Array()
    var from_source := PackedInt32Array()
    z_buffer.resize(count)
    weighted_r.resize(count)
    weighted_g.resize(count)
    weighted_b.resize(count)
    weighted_position.resize(count)
    weights.resize(count)
    from_source.resize(count)
    for i in range(count):
        z_buffer[i] = 1e20
        from_source[i] = -1

    var crop_center: Vector2 = camera.unproject_position(node_world.origin)
    var camera_inverse: Transform3D = camera.global_transform.affine_inverse()
    var accepted: int = 0
    var source_hits := []
    for sid in range(sources.size()):
        var source: Dictionary = sources[sid]
        source_hits.append(0)
        var color_image: Image = source.get("albedo")
        var depth_image: Image = source.get("depth")
        if color_image == null or depth_image == null:
            continue
        if color_image.is_empty() or depth_image.is_empty():
            continue
        var w: int = color_image.get_width()
        var h: int = color_image.get_height()
        if depth_image.get_width() != w or depth_image.get_height() != h:
            continue
        var strength: float = maxf(0.0, float(source.get("weight", 0.0)))
        if strength < 0.0001:
            continue
        var az: int = int(source.get("azimuth", 0))
        var elev: float = float(source.get("elevation", 0.0))
        for py in range(0, h, input_stride):
            for px in range(0, w, input_stride):
                var col: Color = color_image.get_pixel(px, py)
                if col.a < 0.5:
                    continue
                var depth_col: Color = depth_image.get_pixel(px, py)
                var d: float = depth_col.r
                if not is_finite(d):
                    continue
                var u: float = (float(px) + 0.5) / float(w)
                var v: float = (float(py) + 0.5) / float(h)
                var sample_local: Vector3 = Mesher.pixel_position(
                    u, v, d, capture, az, azimuth_steps, elev)
                var world_position: Vector3 = node_world * sample_local
                if camera.is_position_behind(world_position):
                    continue
                var current_z: float = -(camera_inverse * world_position).z
                if current_z < camera.near or current_z > camera.far:
                    continue
                var pixel_position: Vector2 = camera.unproject_position(world_position)
                var gx: int = int(floor(
                    (pixel_position.x - crop_center.x) / crop_screen_pixels * float(size)
                    + float(size) * 0.5))
                var gy: int = int(floor(
                    (pixel_position.y - crop_center.y) / crop_screen_pixels * float(size)
                    + float(size) * 0.5))
                # Small 2x2 splat only to cover subpixel quantization gaps.
                for oy in range(2):
                    for ox in range(2):
                        var x: int = gx + ox
                        var y: int = gy + oy
                        if x < 0 or y < 0 or x >= size or y >= size:
                            continue
                        var index: int = y * size + x
                        if current_z < z_buffer[index] - merge_depth_meters:
                            z_buffer[index] = current_z
                            weighted_position[index] = world_position
                            weighted_r[index] = col.r * strength
                            weighted_g[index] = col.g * strength
                            weighted_b[index] = col.b * strength
                            weights[index] = strength
                            from_source[index] = sid
                            source_hits[sid] = int(source_hits[sid]) + 1
                            accepted += 1
                        elif absf(current_z - z_buffer[index]) <= merge_depth_meters:
                            # Only blend colors when 3D points agree in depth.
                            # Do NOT mix a distant background into foreground.
                            var previous_weight: float = weights[index]
                            var total: float = previous_weight + strength
                            weighted_position[index] = (
                                weighted_position[index] * previous_weight
                                + world_position * strength) / total
                            weighted_r[index] += col.r * strength
                            weighted_g[index] += col.g * strength
                            weighted_b[index] += col.b * strength
                            weights[index] = total

    var positions := PackedVector3Array()
    var colors := PackedColorArray()
    var indices := PackedInt32Array()
    var valid := PackedByteArray()
    var local_inverse: Transform3D = node_world.affine_inverse()
    positions.resize(count)
    colors.resize(count)
    valid.resize(count)
    var coverage: int = 0
    for i in range(count):
        if weights[i] <= 0.0:
            positions[i] = Vector3.ZERO
            colors[i] = Color(0, 0, 0, 0)
            valid[i] = 0
            continue
        positions[i] = local_inverse * weighted_position[i]
        colors[i] = Color(weighted_r[i] / weights[i],
            weighted_g[i] / weights[i], weighted_b[i] / weights[i], 1.0)
        valid[i] = 1
        coverage += 1

    var triangles := 0
    for y in range(size - 1):
        for x in range(size - 1):
            var a: int = y * size + x
            var b: int = a + 1
            var c: int = a + size
            var d: int = c + 1
            for tri in [[a, c, b], [b, c, d]]:
                var a0: int = tri[0]
                var a1: int = tri[1]
                var a2: int = tri[2]
                if valid[a0] == 0 or valid[a1] == 0 or valid[a2] == 0:
                    continue
                var min_z: float = minf(z_buffer[a0],
                    minf(z_buffer[a1], z_buffer[a2]))
                var max_z: float = maxf(z_buffer[a0],
                    maxf(z_buffer[a1], z_buffer[a2]))
                if max_z - min_z > triangle_depth_meters:
                    continue
                indices.append(a0)
                indices.append(a1)
                indices.append(a2)
                triangles += 1

    if indices.is_empty():
        return {"mesh": null, "triangles": 0, "coverage": coverage,
            "source_hits": source_hits, "accepted": accepted}
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = positions
    arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return {"mesh": mesh, "triangles": triangles, "coverage": coverage,
        "source_hits": source_hits, "accepted": accepted}
