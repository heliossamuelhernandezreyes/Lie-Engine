extends "res://scripts/lie_reprojection_node.gd"
## Experimental 4-angle fusion of both azimuth and elevation. Color and
## depth are projected by CPU. Per-pixel normal confidence is optional;
## the separate GPU compute lab tests a real Vulkan fusion kernel.
const Selector = preload("res://scripts/lie_06_view_selector.gd")

@export_range(2, 4, 1) var max_sources: int = 4
@export var use_surface_normals: bool = true
var last_source_codes: Array[String] = []

func _channels(key: String) -> Dictionary:
    if _cache.has(key):
        return _cache[key]
    var source: Dictionary = super._channels(key)
    var n_path := "res://assets/captures/%s/%s.normal.png" % [asset_id,key]
    if ResourceLoader.exists(n_path, "Texture2D"):
        var normal_texture: Texture2D = load(n_path) as Texture2D
        if normal_texture != null and normal_texture.get_width() == source["albedo"].get_width() and normal_texture.get_height() == source["albedo"].get_height():
            source["normal"] = normal_texture.get_image()
    _cache[key] = source
    return source

func rebuild() -> bool:
    var camera: Camera3D = get_viewport().get_camera_3d()
    if camera == null or _capture.is_empty() or output == null:
        return false
    var chosen: Array[Dictionary] = Selector.choose(camera.global_position,
        global_transform, azimuth_steps, elevations, max_sources)
    if chosen.size() < 2:
        return false
    var sources: Array = []
    using_real_capture = true
    last_source_codes.clear()
    for view in chosen:
        var code: String = str(view["code"])
        var raw: Dictionary = _channels(code)
        if raw.is_empty():
            using_real_capture = false
            return false
        using_real_capture = using_real_capture and bool(raw.get("captured",false))
        var data: Dictionary = raw.duplicate()
        data["azimuth"] = view["azimuth"]
        data["elevation"] = view["elevation"]
        data["weight"] = view["weight"]
        if not use_surface_normals:
            data.erase("normal")
        sources.append(data)
        last_source_codes.append(code)
    last_code = " + ".join(last_source_codes)
    var before: int = Time.get_ticks_usec()
    var result: Dictionary = Forward.reconstruct(
        sources, camera, global_transform, _capture,
        azimuth_steps, target_resolution, crop_screen_pixels,
        source_stride, 0.06, 0.19)
    last_build_time_usec = Time.get_ticks_usec() - before
    output.mesh = result["mesh"]
    triangles = int(result["triangles"])
    coverage = int(result["coverage"])
    last_source_hits = result["source_hits"]
    rebuilds += 1
    return output.mesh != null
