extends RefCounted
## Lie 0.4 conservative group visibility: a sphere is outside the view only
## if wholly outside a frustum plane. A rectangular blocker hides a node only
## when its projection encloses ALL eight corners of an enclosing cube.
## This intentionally does NOT cull on a few unreliable ray samples.

static func in_frustum(camera: Camera3D, center_world: Vector3, radius: float) -> bool:
    if camera == null or radius <= 0.0:
        return true
    var planes: Array[Plane] = camera.get_frustum()
    var inside_point: Vector3 = camera.global_position - camera.global_basis.z * (
        camera.near + minf(5.0, maxf(0.01, camera.far - camera.near) * 0.25))
    for plane in planes:
        # Derive the normal orientation using a point known to be in camera view.
        var direction: float = 1.0 if plane.distance_to(inside_point) >= 0.0 else -1.0
        if direction * plane.distance_to(center_world) < -radius:
            return false
    return true


static func covered_by_rectangle(camera_world: Vector3, center_world: Vector3,
        bound_radius: float, wall_transform: Transform3D, half_extent: Vector2) -> bool:
    if bound_radius <= 0.0 or half_extent.x <= 0.0 or half_extent.y <= 0.0:
        return false
    var inverse: Transform3D = wall_transform.affine_inverse()
    var eye: Vector3 = inverse * camera_world
    if absf(eye.z) < 0.0001:
        return false

    # A cube encloses the full spherical proxy; 8 rays are sufficient to show
    # its convex projection is contained in this single planar rectangle.
    # They are NOT sufficient for arbitrary non-convex occluders.
    for sx in [-1.0, 1.0]:
        for sy in [-1.0, 1.0]:
            for sz in [-1.0, 1.0]:
                var world_corner: Vector3 = center_world + Vector3(
                    sx * bound_radius, sy * bound_radius, sz * bound_radius)
                var target: Vector3 = inverse * world_corner
                # Require the camera and ENTIRE cube on opposite wall sides.
                if eye.z * target.z >= -0.0001:
                    return false
                var difference: float = target.z - eye.z
                if absf(difference) < 0.0001:
                    return false
                var fraction: float = -eye.z / difference
                if fraction <= 0.0 or fraction >= 1.0:
                    return false
                var hit: Vector3 = eye.lerp(target, fraction)
                if absf(hit.x) >= half_extent.x - 0.0001 or absf(hit.y) >= half_extent.y - 0.0001:
                    return false
    return true


static func reason(camera: Camera3D, center_world: Vector3, radius: float,
        occluders: Array) -> String:
    if not in_frustum(camera, center_world, radius):
        return "frustum"
    if camera == null:
        return ""
    for wall in occluders:
        if not is_instance_valid(wall) or not wall is Node3D:
            continue
        if not wall.is_inside_tree() or not wall.get("lie_opaque"):
            continue
        var extents: Variant = wall.get("half_extent")
        if extents is Vector2 and covered_by_rectangle(
                camera.global_position, center_world, radius,
                wall.global_transform, extents):
            return "occluded"
    return ""
