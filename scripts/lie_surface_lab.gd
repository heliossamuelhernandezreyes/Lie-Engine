extends Node3D
## LIE-02: compare one image-based surface with a conventional visible 3D
## reference primitive at the same physical camera and lighting settings.
const SurfaceNode = preload("res://scripts/lie_surface_node.gd")

var camera: Camera3D
var lie: Node3D
var reference_mesh: MeshInstance3D
var readout: Label
var angle := 0.0
var light_is_warm := true

func _ready() -> void:
    var env_node := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#0a1726")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.45, 0.5, 0.6)
    env.ambient_light_energy = 0.25
    env_node.environment = env
    add_child(env_node)

    var collider := StaticBody3D.new()
    collider.name = "InvisiblePhysicsProxy"
    var shape := CollisionShape3D.new()
    shape.name = "CollisionShape3D"
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.65
    capsule.height = 2.8
    shape.shape = capsule
    shape.position.y = 1.4
    collider.add_child(shape)
    add_child(collider)

    lie = SurfaceNode.new()
    lie.name = "LieSurfaceNode"
    lie.position = Vector3(0.0, 1.4, 0.0)
    add_child(lie)

    reference_mesh = MeshInstance3D.new()
    reference_mesh.name = "Reference3D"
    var primitive := BoxMesh.new()
    primitive.size = Vector3(1.4, 2.6, 0.65)
    reference_mesh.mesh = primitive
    reference_mesh.position = Vector3(3.5, 1.4, 0)
    reference_mesh.visible = false  # A/B reference, not rendered by Lie.
    add_child(reference_mesh)

    camera = Camera3D.new()
    camera.name = "LieCamera"
    camera.current = true
    camera.fov = 50
    add_child(camera)

    var ui := CanvasLayer.new()
    add_child(ui)
    readout = Label.new()
    readout.position = Vector2(20, 20)
    readout.add_theme_font_size_override("font_size", 20)
    readout.add_theme_color_override("font_color", Color("#ddf2fa"))
    ui.add_child(readout)
    _position_camera()
    lie.call("update_surface")

func _process(delta: float) -> void:
    angle += delta * (0.18 + Input.get_axis("ui_left", "ui_right"))
    if Input.is_action_just_pressed("ui_accept"):
        set_warm_light(not light_is_warm)
    _position_camera()
    lie.call("update_surface")
    var src := "real channels" if bool(lie.get("using_captured_surface")) else "synthetic channels"
    readout.text = "LIE-02 | Color + Normal + Depth\n" +         "Camera key: %s | %s\n" % [str(lie.get("current_view_code")), src] +         "Space: toggle warm/cool light | arrows: orbit\n" +         "Reference cube at X=3.5 (hidden, for explicit A/B tests)"

func set_warm_light(warm: bool) -> void:
    light_is_warm = warm
    lie.call("set_light_color", Color(1.0, 0.22, 0.07) if warm else Color(0.07, 0.28, 1.0))

func _position_camera() -> void:
    camera.position = Vector3(7.2 * sin(angle), 3.1, 7.2 * cos(angle))
    camera.look_at(Vector3(0, 1.4, 0), Vector3.UP)
