extends Node3D
## Lie 0.4: paired depth-mesh views with stable dithered angular transitions.
## Conservative FRUSTUM and authored rectangular occluder culling is performed
## BEFORE loading PNGs and constructing depth geometry. Neither source 3D
## meshes nor their source polygons are rendered.
const ViewIndex = preload("res://scripts/lie_view_index.gd")
const Mesher = preload("res://scripts/lie_depth_mesher.gd")
const Pair = preload("res://scripts/lie_angular_pair.gd")
const Visibility = preload("res://scripts/lie_visibility.gd")
const SURFACE_SHADER = preload("res://shaders/lie_depth_surface.gdshader")

@export var asset_id: String = "demo_shard"
@export_range(4, 64) var azimuth_steps: int = 16
@export var elevation_degrees: PackedFloat32Array = PackedFloat32Array([-30.0, 0.0, 30.0])
@export_range(1, 16, 1) var reconstruction_stride: int = 2
@export_range(2, 12, 1) var max_cached_views: int = 4
@export_range(1.0, 3.0, 0.1) var bounds_multiplier: float = 1.75
@export var enable_frustum_culling: bool = true
@export var enable_static_occlusion: bool = true
@export var node_tint := Color.WHITE

var current_view_code := ""
var next_view_code := ""
var view_blend := 0.0
var using_captured_surface := false
var current_triangle_count := 0
var view_changes := 0
var geometry_builds := 0
var skipped_for_visibility := 0
var visibility_reason := ""
var cache: Dictionary = {}
var _cache_fifo: Array[String] = []
var _capture: Dictionary = {}
var material: ShaderMaterial
var secondary_material: ShaderMaterial
var surface: MeshInstance3D
var surface_next: MeshInstance3D
var light_direction_world := Vector3(0.3, 0.2, 1.0)

func _ready() -> void:
    surface = MeshInstance3D.new()
    surface.name = "DepthSurface"
    add_child(surface)
    surface_next = MeshInstance3D.new()
    surface_next.name = "DepthSurfaceNext"
    add_child(surface_next)
    material = _new_material(false)
    secondary_material = _new_material(true)
    surface.material_override = material
    surface_next.material_override = secondary_material
    _capture = _read_capture()
    update_surface()

func _new_material(second: bool) -> ShaderMaterial:
    var m := ShaderMaterial.new()
    m.shader = SURFACE_SHADER
    m.set_shader_parameter("second_pass", second)
    m.set_shader_parameter("node_tint", Vector3(node_tint.r, node_tint.g, node_tint.b))
    m.set_shader_parameter("light_rgb", Vector3(1.0, 0.86, 0.70))
    return m

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
    for m in [material, secondary_material]:
        if m != null:
            m.set_shader_parameter("light_rgb", Vector3(color.r, color.g, color.b))

func set_light_direction(direction: Vector3) -> void:
    if direction.length_squared() > 0.00001:
        light_direction_world = direction.normalized()

func _visibility_reason(camera: Camera3D) -> String:
    if not enable_frustum_culling and not enable_static_occlusion:
        return ""
    var radius: float = float(_capture["radius"]) * bounds_multiplier
    var frame_scale: Vector3 = global_transform.basis.get_scale()
    radius *= maxf(frame_scale.x, maxf(frame_scale.y, frame_scale.z))
    if enable_frustum_culling and not Visibility.in_frustum(camera, global_position, radius):
        return "frustum"
    if enable_static_occlusion:
        return Visibility.reason(camera, global_position, radius,
            get_tree().get_nodes_in_group("lie_occluders"))
    return ""

func update_surface() -> void:
    var camera: Camera3D = get_viewport().get_camera_3d()
    if camera == null or surface == null:
        return
    visibility_reason = _visibility_reason(camera)
    if visibility_reason != "":
        surface.visible = false
        surface_next.visible = false
        skipped_for_visibility += 1
        # Crucially: NO angular lookup, PNG load, mesh creation or GPU upload.
        return

    var pair: Dictionary = Pair.choose(
        camera.global_position, global_transform, azimuth_steps, elevation_degrees)
    var primary: String = str(pair["first_code"])
    var secondary: String = str(pair["next_code"])
    var t: float = float(pair["weight"])
    var require_next: bool = t > 0.001
    var before: String = current_view_code
    current_view_code = str(pair["nearest_code"])
    next_view_code = secondary if require_next else ""
    view_blend = t
    if before != current_view_code:
        view_changes += 1
    var first_entry: Dictionary = _view(primary, int(pair["first"]),
        int(pair["elevation"]), float(pair["elevation_degrees"]))
    _show_view(surface, material, first_entry, t)
    using_captured_surface = bool(first_entry["captured"])
    if require_next:
        var next_entry: Dictionary = _view(secondary, int(pair["next"]),
            int(pair["elevation"]), float(pair["elevation_degrees"]))
        _show_view(surface_next, secondary_material, next_entry, t)
        using_captured_surface = using_captured_surface and bool(next_entry["captured"])
        current_triangle_count = int(first_entry["triangles"]) + int(next_entry["triangles"])
    else:
        surface_next.visible = false
        surface_next.mesh = null
        current_triangle_count = int(first_entry["triangles"])
    _evict_except([primary, secondary] if require_next else [primary])
    var direction_local: Vector3 = global_transform.basis.orthonormalized().inverse() * light_direction_world
    for m in [material, secondary_material]:
        m.set_shader_parameter("light_direction_local", direction_local.normalized())

func _show_view(target: MeshInstance3D, mat: ShaderMaterial,
        entry: Dictionary, t: float) -> void:
    target.mesh = entry["mesh"]
    target.visible = target.mesh != null
    mat.set_shader_parameter("lie_albedo", entry["albedo"])
    mat.set_shader_parameter("lie_normal", entry["normal"])
    mat.set_shader_parameter("view_blend", t)

func _view(key: String, az: int, el: int, elev_degrees: float) -> Dictionary:
    if cache.has(key):
        return cache[key]
    var data: Dictionary = _get_channels(key, az, el)
    var albedo: Image = data["albedo"].get_image()
    var depth: Image = data["depth"].get_image()
    var result: Dictionary = Mesher.build_mesh(albedo, depth, _capture, az,
        azimuth_steps, elev_degrees, reconstruction_stride)
    data["mesh"] = result["mesh"]
    data["triangles"] = int(result["triangles"])
    geometry_builds += 1
    cache[key] = data
    _cache_fifo.append(key)
    return data

func _evict_except(active: Array) -> void:
    # FIFO only removes inactive views. Two active views are never evicted.
    while _cache_fifo.size() > max_cached_views:
        var key: String = _cache_fifo.pop_front()
        if key in active:
            _cache_fifo.append(key)
        else:
            cache.erase(key)

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
    # Clearly labeled fallback: not actual captured 3D image.
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
