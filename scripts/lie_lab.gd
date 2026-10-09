extends Node3D
## LIE-01 demonstration: a static collision proxy stays in 3D; only one
## camera-selected textured billboard is ever visible for the object.
const LieNode = preload("res://scripts/lie_node.gd")

var camera: Camera3D
var visual_node: Node3D
var readout: Label
var angle: float = 0.0
var elapsed: float = 0.0


func _ready() -> void:
    var backdrop := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#0a1726")
    backdrop.environment = env
    add_child(backdrop)

    var body := StaticBody3D.new()
    body.name = "InvisiblePhysicsProxy"
    var shape := CollisionShape3D.new()
    shape.name = "CollisionShape3D"
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.65
    capsule.height = 2.8
    shape.shape = capsule
    shape.position.y = 1.4
    body.add_child(shape)
    add_child(body)

    visual_node = LieNode.new()
    visual_node.name = "LieNode_Demo"
    var sprite := Sprite3D.new()
    sprite.name = "Visual"
    visual_node.add_child(sprite)
    add_child(visual_node)

    camera = Camera3D.new()
    camera.name = "LieCamera"
    camera.fov = 52.0
    camera.current = true
    add_child(camera)

    var ui := CanvasLayer.new()
    add_child(ui)
    readout = Label.new()
    readout.position = Vector2(24, 22)
    readout.add_theme_font_size_override("font_size", 22)
    readout.add_theme_color_override("font_color", Color("#daf9ff"))
    ui.add_child(readout)
    _move_camera()


func _process(delta: float) -> void:
    elapsed += delta
    angle += (0.32 + Input.get_axis("ui_left", "ui_right") * 1.5) * delta
    _move_camera()
    var key: String = str(visual_node.get("current_view_code"))
    var captured: bool = bool(visual_node.get("using_captured_image"))
    readout.text = "LIE-01 | camera-indexed visual node\n" + \
        ("View: %s | Source: %s\n" % [key,
        "captured PNG" if captured else "synthetic placeholder"]) + \
        "Physics: invisible CapsuleShape3D | LEFT / RIGHT: orbit control\n" + \
        "Angle: %.1f degrees | No source mesh is drawn" % fposmod(rad_to_deg(angle), 360.0)


func _move_camera() -> void:
    camera.global_position = Vector3(7.5 * sin(angle), 3.35 + 0.8 * sin(angle * 0.42),
        7.5 * cos(angle))
    camera.look_at(Vector3(0, 1.4, 0), Vector3.UP)
