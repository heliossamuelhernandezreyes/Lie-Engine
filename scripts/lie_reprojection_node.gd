extends Node3D
## Lie 0.5: bounded CPU novel-view reprojection reference.
## Reconstructs from TWO REAL captured depth+albedo view pairs into a
## target perspective camera. Normals remain captured for future relighting.
## Every rebuild is potentially expensive: do NOT assume it is mobile-ready.
const Pair = preload("res://scripts/lie_angular_pair.gd")
const Mesher = preload("res://scripts/lie_depth_mesher.gd")
const Forward = preload("res://scripts/lie_forward_reprojector.gd")
const SHADER = preload("res://shaders/lie_reprojection.gdshader")

@export var asset_id := "demo_shard"
@export_range(4, 64, 1) var azimuth_steps := 16
@export var elevations := PackedFloat32Array([-30.0, 0.0, 30.0])
@export_range(32, 256, 1) var target_resolution := 128
@export_range(1, 8, 1) var source_stride := 2
@export_range(100.0, 800.0, 1.0) var crop_screen_pixels := 350.0
@export var automatically_update := false
@export var tint := Color.WHITE

var _capture := {}
var _cache := {}
var output: MeshInstance3D
var last_code := ""
var coverage := 0
var triangles := 0
var rebuilds := 0
var using_real_capture := false
var last_source_hits := []
var last_build_time_usec := 0

func _ready() -> void:
    output = MeshInstance3D.new()
    output.name = "ReprojectedSurface"
    add_child(output)
    var shader_mat := ShaderMaterial.new()
    shader_mat.shader = SHADER
    shader_mat.set_shader_parameter("scene_tint", Vector3(tint.r, tint.g, tint.b))
    output.material_override = shader_mat
    _capture = _load_capture()
    if automatically_update:
        rebuild()

func _process(_delta: float) -> void:
    if automatically_update:
        rebuild()

func _load_capture() -> Dictionary:
    var manifest_path := "res://assets/captures/%s/manifest.json" % asset_id
    if not FileAccess.file_exists(manifest_path):
        return {}
    var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
    if not json is Dictionary:
        return {}
    return Mesher.capture_from_manifest(json)

func _channels(key: String) -> Dictionary:
    if _cache.has(key):
        return _cache[key]
    var path: String = "res://assets/captures/%s/%s" % [asset_id, key]
    var cp: String = path + ".albedo.png"
    var dp: String = path + ".depth.png"
    if not ResourceLoader.exists(cp, "Texture2D") or not ResourceLoader.exists(dp, "Texture2D"):
        return {}
    var color: Texture2D = load(cp) as Texture2D
    var depth: Texture2D = load(dp) as Texture2D
    if color == null or depth == null or color.get_size() != depth.get_size():
        return {}
    var entry: Dictionary = {
        "albedo": color.get_image(), "depth": depth.get_image()
    }
    _cache[key] = entry
    return entry

func rebuild() -> bool:
    var camera: Camera3D = get_viewport().get_camera_3d()
    if camera == null or _capture.is_empty() or output == null:
        return false
    if elevations.is_empty():
        return false
    var pair: Dictionary = Pair.choose(camera.global_position, global_transform,
        azimuth_steps, elevations)
    last_code = "%s + %s" % [pair["first_code"], pair["next_code"]]
    var source_a: Dictionary = _channels(str(pair["first_code"]))
    var source_b: Dictionary = _channels(str(pair["next_code"]))
    if source_a.is_empty() or source_b.is_empty():
        using_real_capture = false
        output.mesh = null
        return false
    using_real_capture = true
    var first: Dictionary = source_a.duplicate()
    var second: Dictionary = source_b.duplicate()
    first["azimuth"] = int(pair["first"])
    second["azimuth"] = int(pair["next"])
    first["elevation"] = float(pair["elevation_degrees"])
    second["elevation"] = float(pair["elevation_degrees"])
    var t: float = float(pair["weight"])
    first["weight"] = maxf(0.0001, 1.0 - t)
    second["weight"] = maxf(0.0001, t)
    var before: int = Time.get_ticks_usec()
    var result: Dictionary = Forward.reconstruct(
        [first, second], camera, global_transform, _capture,
        azimuth_steps, target_resolution, crop_screen_pixels, source_stride)
    last_build_time_usec = Time.get_ticks_usec() - before
    output.mesh = result["mesh"]
    triangles = int(result["triangles"])
    coverage = int(result["coverage"])
    last_source_hits = result["source_hits"]
    rebuilds += 1
    return output.mesh != null
