extends RefCounted
## Continuous camera-local angular confidence across azimuth AND elevation.
## Select up to 4 angular views, not four arbitrary PNGs.
const ViewIndex = preload("res://scripts/lie_view_index.gd")

static func choose(camera_world: Vector3, node_frame: Transform3D,
        azimuth_steps: int, elevations: PackedFloat32Array,
        max_sources: int = 4) -> Array[Dictionary]:
    if azimuth_steps < 4 or elevations.is_empty() or max_sources < 1:
        return []
    var local: Vector3 = node_frame.basis.orthonormalized().inverse() * (
        camera_world - node_frame.origin)
    if local.length_squared() <= 0.0000001:
        return []
    var target: Vector3 = local.normalized()
    var scored: Array[Dictionary] = []
    for el in range(elevations.size()):
        for az in range(azimuth_steps):
            var normal: Vector3 = ViewIndex.direction_for_view(
                az, azimuth_steps, elevations[el])
            var similarity: float = maxf(0.0, target.dot(normal))
            var confidence: float = pow(similarity, 8.0)
            if confidence > 0.0001:
                scored.append({
                    "azimuth": az, "elevation_index": el,
                    "elevation": float(elevations[el]),
                    "code": "az_%02d_el_%02d" % [az, el],
                    "weight": confidence
                })
    scored.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
        return float(a["weight"]) > float(b["weight"]))
    var picked: Array[Dictionary] = []
    var total: float = 0.0
    for i in range(mini(max_sources, scored.size())):
        total += float(scored[i]["weight"])
        picked.append(scored[i])
    if total > 0.0000001:
        for item in picked:
            item["weight"] = float(item["weight"]) / total
    return picked
