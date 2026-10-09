extends RefCounted
## LIE-01 pure math. The +Z local axis is azimuth 0; +X is azimuth 90.
## Camera position is transformed into the node's LOCAL rotation frame.
## This is discrete nearest-view selection, not view synthesis.

static func select_view(camera_world: Vector3, node_world: Transform3D,
        azimuth_steps: int, elevation_degrees: PackedFloat32Array) -> Dictionary:
    assert(azimuth_steps >= 4, "At least 4 azimuth steps required")
    assert(not elevation_degrees.is_empty(), "At least one elevation required")

    # Orthonormalizing keeps angular selection independent from mesh scale.
    var local: Vector3 = node_world.basis.orthonormalized().inverse() * (camera_world - node_world.origin)
    var horizontal: float = Vector2(local.x, local.z).length()
    var azimuth: float = fposmod(rad_to_deg(atan2(local.x, local.z)), 360.0)
    var increment: float = 360.0 / float(azimuth_steps)
    var az_index: int = posmod(int(floor(azimuth / increment + 0.5)), azimuth_steps)
    var elevation: float = rad_to_deg(atan2(local.y, horizontal))
    var el_index: int = 0
    var smallest_error: float = INF
    for i in range(elevation_degrees.size()):
        var error: float = absf(elevation - elevation_degrees[i])
        if error < smallest_error:
            el_index = i
            smallest_error = error

    return {
        "azimuth_index": az_index,
        "elevation_index": el_index,
        "azimuth_degrees": azimuth,
        "elevation_degrees": elevation,
        "distance": local.length(),
        "code": "az_%02d_el_%02d" % [az_index, el_index]
    }


static func direction_for_view(azimuth_index: int, azimuth_steps: int,
        elevation_degrees: float) -> Vector3:
    var a: float = TAU * float(azimuth_index) / float(azimuth_steps)
    var e: float = deg_to_rad(elevation_degrees)
    return Vector3(sin(a) * cos(e), sin(e), cos(a) * cos(e))
