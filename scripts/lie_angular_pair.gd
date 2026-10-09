extends RefCounted
## Lie 0.4: continuous weights for neighboring azimuth samples, not discrete
## nearest-neighbor snapping at midpoints. Elevation remains nearest neighbor.
const ViewIndex = preload("res://scripts/lie_view_index.gd")

static func choose(camera_world: Vector3, node_transform: Transform3D,
        azimuth_steps: int, elevations: PackedFloat32Array) -> Dictionary:
    var pose: Dictionary = ViewIndex.select_view(
        camera_world, node_transform, azimuth_steps, elevations)
    var step: float = 360.0 / float(azimuth_steps)
    var coordinate: float = float(pose["azimuth_degrees"]) / step
    var first: int = posmod(int(floor(coordinate)), azimuth_steps)
    var next: int = (first + 1) % azimuth_steps
    var t: float = clampf(coordinate - floor(coordinate), 0.0, 1.0)
    var elevation: int = int(pose["elevation_index"])
    return {
        "first": first, "next": next,
        "weight": t, "elevation": elevation,
        "first_code": "az_%02d_el_%02d" % [first, elevation],
        "next_code": "az_%02d_el_%02d" % [next, elevation],
        "nearest_code": pose["code"],
        "elevation_degrees": float(elevations[elevation])
    }
