extends Node3D
## One Lie visual node stands for an entire rigid visual group.
## Parent 3D physics / skeleton are not represented by this Sprite3D mesh.
const ViewIndex = preload("res://scripts/lie_view_index.gd")

@export var asset_id: String = "demo_shard"
@export_range(4, 64, 1) var azimuth_steps: int = 16
@export var elevation_degrees: PackedFloat32Array = PackedFloat32Array([-30.0, 0.0, 30.0])

var current_view_code: String = ""
var using_captured_image: bool = false
var view_changes: int = 0
var cache: Dictionary = {}

@onready var visual: Sprite3D = get_node("Visual") as Sprite3D


func _ready() -> void:
    assert(visual != null, "Lie visual node requires child Sprite3D called Visual")
    # A billboard faces the camera, but the INDEX uses the unmodified 3D frame.
    visual.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    visual.shaded = false
    visual.pixel_size = 0.014
    visual.centered = true
    visual.position.y = 1.4


func _process(_delta: float) -> void:
    var camera: Camera3D = get_viewport().get_camera_3d()
    if camera == null:
        return
    var pose: Dictionary = ViewIndex.select_view(
        camera.global_position, global_transform, azimuth_steps, elevation_degrees)
    var key: String = pose["code"]
    if key == current_view_code:
        return

    current_view_code = key
    view_changes += 1
    if not cache.has(key):
        var path: String = "res://assets/captures/%s/%s.png" % [asset_id, key]
        var from_disk: Texture2D = null
        if ResourceLoader.exists(path, "Texture2D"):
            from_disk = load(path) as Texture2D
        if from_disk != null:
            cache[key] = {"texture": from_disk, "captured": true}
        else:
            cache[key] = {"texture": _placeholder(pose["azimuth_index"],
                pose["elevation_index"]), "captured": false}

    visual.texture = cache[key]["texture"]
    using_captured_image = bool(cache[key]["captured"])


func _placeholder(az: int, el: int) -> ImageTexture:
    # A synthetic side-dependent silhouette demonstrates angular selection.
    # It is NOT photogrammetry, a normal map, or a production visual.
    var img: Image = Image.create(128, 192, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0))
    var phase: float = TAU * float(az) / float(azimuth_steps)
    var offset: float = 0.08 * sin(phase)
    var tint: Color = Color(0.22 + 0.22 * cos(phase), 0.64,
        0.75 - 0.18 * sin(phase), 1.0)
    for y in range(192):
        var v: float = float(y) / 191.0
        var half_width: float = (0.07 + pow(v, 1.4) * 0.23)
        var center_x: float = 0.50 + offset + 0.08 * (1.0 - v) * sin(2.0 * phase)
        for x in range(128):
            var u: float = float(x) / 127.0
            if absf(u - center_x) <= half_width:
                var edge: float = 1.0 - absf(u - center_x) / half_width
                var shade: float = 0.56 + 0.37 * edge + 0.06 * float(el)
                img.set_pixel(x, y, tint * shade)
    return ImageTexture.create_from_image(img)
