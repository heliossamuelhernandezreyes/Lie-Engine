extends Node3D
## LIE-03 node: one grouped rigid asset reconstructed from a captured depth view.
## Surface mesh is NOT a source model: triangles are reconstructed from depth
## samples and discarded at silhouettes/discontinuities. Unseen sides stay unseen.
const ViewIndex = preload("res://scripts/lie_view_index.gd")
const Mesher = preload("res://scripts/lie_depth_mesher.gd")
const SURFACE_SHADER = preload("res://shaders/lie_depth_surface.gdshader")

@export var asset_id: String = "demo_shard"
@export_range(4, 64) var azimuth_steps: int = 16
@export var elevation_degrees: PackedFloat32Array = PackedFloat32Array([-30.0, 0.0, 30.0])
@export_range(1, 16, 1) var reconstruction_stride: int = 2
@export_range(1, 8, 1) var max_cached_views: int = 3
@export var node_tint := Color.WHITE

var current_view_code := ""
var using_captured_surface := false
var current_triangle_count := 0
var view_changes := 0
var cache: Dictionary = {}
var _cache_fifo: Array[String] = []
var _capture: Dictionary = {}
var material: ShaderMaterial
var surface: MeshInstance3D
var light_direction_world := Vector3(0.3, 0.2, 1.0)

func _ready() -> void:
    surface = MeshInstance3D.new()
    surface.name = "DepthSurface"
    add_child(surface)
    material = ShaderMaterial.new()
    material.shader = SURFACE_SHADER
    surface.material_override = material
    material.set_shader_parameter("node_tint", Vector3(node_tint.r, node_tint.g, node_tint.b))
    material.set_shader_parameter("light_rgb", Vector3(1.0, 0.86, 0.70))
    _capture = _read_capture()
    update_surface()

func _read_capture() -> Dictionary:
    var file := "res://assets/captures/%s/manifest.json" % asset_id
    if FileAccess.file_exists(file):
        var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
        if parsed is Dictionary:
            var data: Dictionary = Mesher.capture_from_manifest(parsed)
            if not data.is_empty():
                return data
    return Mesher.default_capture()

func set_light_color(color: Color) -> void:
    if material != null:
        material.set_shader_parameter("light_rgb", Vector3(color.r, color.g, color.b))

func set_light_direction(direction: Vector3) -> void:
    if direction.length_squared() > 0.00001:
        light_direction_world = direction.normalized()

func update_surface() -> void:
    var cam: Camera3D = get_viewport().get_camera_3d()
    if cam == null or surface == null:
        return
    var pose: Dictionary = ViewIndex.select_view(cam.global_position, global_transform,
        azimuth_steps, elevation_degrees)
    var key: String = str(pose["code"])
    if key != current_view_code:
        current_view_code = key
        view_changes += 1
        if not cache.has(key):
            var channels: Dictionary = _get_channels(key, int(pose["azimuth_index"]),
                int(pose["elevation_index"]))
            var result: Dictionary = Mesher.build_mesh(
                channels["albedo"].get_image(), channels["depth"].get_image(),
                _capture, int(pose["azimuth_index"]), azimuth_steps,
                float(elevation_degrees[int(pose["elevation_index"])]),
                reconstruction_stride)
            channels["mesh"] = result["mesh"]
            channels["triangles"] = int(result["triangles"])
            cache[key] = channels
            _cache_fifo.append(key)
        var entry: Dictionary = cache[key]
        surface.mesh = entry["mesh"]
        using_captured_surface = bool(entry["captured"])
        current_triangle_count = int(entry["triangles"])
        material.set_shader_parameter("lie_albedo", entry["albedo"])
        material.set_shader_parameter("lie_normal", entry["normal"])
        # Bounded FIFO: evict other views, never evict the current view.
        while _cache_fifo.size() > max_cached_views:
            var remove_key: String = _cache_fifo.pop_front()
            if remove_key != key:
                cache.erase(remove_key)
    var dir_local: Vector3 = global_transform.basis.orthonormalized().inverse() * light_direction_world
    material.set_shader_parameter("light_direction_local", dir_local.normalized())

func _process(_delta: float) -> void:
    update_surface()

func _get_channels(key: String, az: int, _el: int) -> Dictionary:
    var root_path := "res://assets/captures/%s/%s" % [asset_id, key]
    var c_path := root_path + ".albedo.png"
    var n_path := root_path + ".normal.png"
    var d_path := root_path + ".depth.png"
    if ResourceLoader.exists(c_path, "Texture2D") and ResourceLoader.exists(n_path, "Texture2D") and ResourceLoader.exists(d_path, "Texture2D"):
        var c := load(c_path) as Texture2D
        var n := load(n_path) as Texture2D
        var d := load(d_path) as Texture2D
        if c != null and n != null and d != null and c.get_size() == n.get_size() and c.get_size() == d.get_size():
            return {"albedo": c, "normal": n, "depth": d, "captured": true}
    return _synthetic_view(az)

func _synthetic_view(az: int) -> Dictionary:
    # Deterministic, openly synthetic disc for checkout without Blender assets.
    # Front depth curves in metres relative to sample camera; not photogrammetry.
    var side := 96
    var albedo := Image.create(side, side, false, Image.FORMAT_RGBA8)
    var normal := Image.create(side, side, false, Image.FORMAT_RGBA8)
    var depth := Image.create(side, side, false, Image.FORMAT_RGBA8)
    var phase := TAU * float(az) / float(azimuth_steps)
    for y in range(side):
        for x in range(side):
            var u: float = (float(x) + 0.5) / float(side)
            var v: float = (float(y) + 0.5) / float(side)
            var xx: float = (u - 0.5) / 0.38
            var yy: float = (v - 0.5) / 0.42
            var inside: bool = xx * xx + yy * yy < 0.94
            var bulge: float = sqrt(maxf(0.0, 1.0 - xx * xx - yy * yy))
            var norm_depth: float = 0.48 - 0.29 * bulge
            var n := Vector3(xx * 0.67, -yy * 0.67, bulge).normalized()
            var opaque: float = 1.0 if inside else 0.0
            albedo.set_pixel(x, y, Color(0.72 + 0.08 * cos(phase), 0.75,
                0.79 + 0.07 * sin(phase), opaque))
            normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5,
                -n.z * 0.5 + 0.5, n.y * 0.5 + 0.5, opaque))
            depth.set_pixel(x, y, Color(norm_depth, norm_depth, norm_depth, opaque))
    return {"albedo": ImageTexture.create_from_image(albedo),
        "normal": ImageTexture.create_from_image(normal),
        "depth": ImageTexture.create_from_image(depth), "captured": false}
