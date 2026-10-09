extends Node3D
## LIE-02: one rigid group, nearest-view albedo/normal/depth and local relighting.
## The mesh of the source asset is NEVER rendered here. No depth writeback yet.
const ViewIndex = preload("res://scripts/lie_view_index.gd")
const SURFACE_SHADER = preload("res://shaders/lie_surface.gdshader")

@export var asset_id: String = "demo_shard"
@export_range(4, 64, 1) var azimuth_steps: int = 16
@export var elevation_degrees: PackedFloat32Array = PackedFloat32Array([-30.0, 0.0, 30.0])
var current_view_code: String = ""
var view_changes: int = 0
var using_captured_surface: bool = false
var cache: Dictionary = {}
var surface_material: ShaderMaterial
var visual: Sprite3D
var light_color := Color(1.0, 0.86, 0.74)
var light_direction_world := Vector3(0.30, 0.20, 1.0)

func _ready() -> void:
    visual = Sprite3D.new()
    visual.name = "LieSurfaceVisual"
    visual.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    visual.pixel_size = 0.018
    visual.shaded = false
    visual.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    add_child(visual)
    surface_material = ShaderMaterial.new()
    surface_material.shader = SURFACE_SHADER
    visual.material_override = surface_material
    set_light_color(light_color)
    update_surface()

func set_light_color(color: Color) -> void:
    light_color = color
    if surface_material != null:
        surface_material.set_shader_parameter("light_rgb", Vector3(color.r, color.g, color.b))
        surface_material.set_shader_parameter("light_intensity", 1.0)

func set_light_direction(direction: Vector3) -> void:
    if direction.length_squared() > 0.00001:
        light_direction_world = direction.normalized()

func update_surface() -> void:
    var camera := get_viewport().get_camera_3d()
    if camera == null or surface_material == null:
        return
    var pose: Dictionary = ViewIndex.select_view(
        camera.global_position, global_transform, azimuth_steps, elevation_degrees)
    var key: String = pose["code"]
    if key != current_view_code:
        current_view_code = key
        view_changes += 1
        if not cache.has(key):
            cache[key] = _load_channels(key, int(pose["azimuth_index"]),
                int(pose["elevation_index"]))
        var channels: Dictionary = cache[key]
        using_captured_surface = bool(channels["captured"])
        visual.texture = channels["albedo"]
        surface_material.set_shader_parameter("lie_albedo", channels["albedo"])
        surface_material.set_shader_parameter("lie_normal", channels["normal"])
        surface_material.set_shader_parameter("lie_depth", channels["depth"])

    var step: float = 360.0 / float(azimuth_steps)
    var az_residual: float = wrapf(float(pose["azimuth_degrees"]) -
        float(pose["azimuth_index"]) * step, -180.0, 180.0)
    var el_residual: float = (float(pose["elevation_degrees"])
        - float(elevation_degrees[int(pose["elevation_index"])]))
    # Residuals are bounded angular fractions. Not a geometric reprojection.
    surface_material.set_shader_parameter("view_delta",
        Vector2(clampf(az_residual / step, -1.0, 1.0),
                clampf(el_residual / 30.0, -1.0, 1.0)))
    var dir_local: Vector3 = global_transform.basis.orthonormalized().inverse() * light_direction_world
    surface_material.set_shader_parameter("light_direction_local", dir_local.normalized())

func _process(_delta: float) -> void:
    update_surface()

func _load_channels(key: String, az: int, el: int) -> Dictionary:
    var root := "res://assets/captures/%s/%s" % [asset_id, key]
    var albedo := root + ".albedo.png"
    var normal := root + ".normal.png"
    var depth := root + ".depth.png"
    if ResourceLoader.exists(albedo, "Texture2D") and ResourceLoader.exists(normal, "Texture2D") and ResourceLoader.exists(depth, "Texture2D"):
        var color_tex := load(albedo) as Texture2D
        var normal_tex := load(normal) as Texture2D
        var depth_tex := load(depth) as Texture2D
        if color_tex != null and normal_tex != null and depth_tex != null and color_tex.get_size() == normal_tex.get_size() and color_tex.get_size() == depth_tex.get_size():
            return {"albedo": color_tex, "normal": normal_tex, "depth": depth_tex, "captured": true}
    return _synthetic_channels(az, el)

func _synthetic_channels(az: int, _el: int) -> Dictionary:
    # Synthetic fixture contains NON-PLANAR depth and directional normals.
    # It proves the channel wiring, never photo-realism.
    var side := 96
    var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
    var normal := Image.create(side, side, false, Image.FORMAT_RGBA8)
    var depth := Image.create(side, side, false, Image.FORMAT_RGBA8)
    var phase := TAU * float(az) / float(azimuth_steps)
    for y in range(side):
        for x in range(side):
            var u := (float(x) + 0.5) / float(side)
            var v := (float(y) + 0.5) / float(side)
            var cx := (u - 0.5) * 2.0
            var cy := (v - 0.5) * 2.0
            var inside := absf(cx) < 0.58 and absf(cy) < 0.82
            var thickness := sqrt(maxf(0.0, 1.0 - pow(cx / 0.60, 2.0) - pow(cy / 0.92, 2.0)))
            var z := 0.70 - 0.55 * thickness
            var nx := clampf(cx * 0.7, -0.8, 0.8)
            var ny := clampf(cy * 0.5, -0.8, 0.8)
            var nz := sqrt(maxf(0.02, 1.0 - nx * nx - ny * ny))
            image.set_pixel(x, y, Color(0.50 + 0.15 * cos(phase),
                0.55 + 0.12 * sin(phase), 0.65, 1.0 if inside else 0.0))
            # Lie-local (nx,ny,nz) -> Blender-world (nx,-nz,ny)
            normal.set_pixel(x, y, Color(nx * 0.5 + 0.5,
                -nz * 0.5 + 0.5, ny * 0.5 + 0.5, 1.0 if inside else 0.0))
            depth.set_pixel(x, y, Color(z, z, z, 1.0 if inside else 0.0))
    return {"albedo": ImageTexture.create_from_image(image),
        "normal": ImageTexture.create_from_image(normal),
        "depth": ImageTexture.create_from_image(depth), "captured": false}
