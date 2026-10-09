extends Node3D
## Depth-reconstructed LIE-03 nodes overlap spatially, with genuine GPU Z tests.
## A conventional source model is never drawn. Geometry is generated from depth.
const LieDepthNode = preload("res://scripts/lie_depth_node.gd")

var camera: Camera3D
var red_node: Node3D
var blue_node: Node3D
var readout: Label
var orbit := 0.0
var rotating := true
var warm_light := true

func _ready() -> void:
    var ambient := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.045, 0.060, 0.088)
    ambient.environment = env
    add_child(ambient)
    _new_node("NearRedGroup", Vector3(0, 1.4, 0.55), Color(1.0, 0.18, 0.18))
    _new_node("FarBlueGroup", Vector3(0, 1.4, -1.45), Color(0.18, 0.28, 1.0))
    camera = Camera3D.new()
    camera.name = "LieCamera"
    camera.current = true
    camera.fov = 48.0
    add_child(camera)
    var layer := CanvasLayer.new()
    add_child(layer)
    readout = Label.new()
    readout.position = Vector2(20, 20)
    readout.add_theme_font_size_override("font_size", 20)
    readout.add_theme_color_override("font_color", Color("#d2efff"))
    layer.add_child(readout)
    _position_camera()
    for node in [red_node, blue_node]:
        node.call("update_surface")

func _new_node(id: String, pos: Vector3, tint: Color) -> void:
    var lie = LieDepthNode.new()
    lie.name = id
    lie.position = pos
    lie.node_tint = tint
    # Default capture asset from Blender: 16x3. CI tests set 4x3.
    add_child(lie)
    var body := StaticBody3D.new()
    body.name = id + "_InvisibleCollider"
    body.position = pos
    var shape := CollisionShape3D.new()
    var capsule := SphereShape3D.new()
    capsule.radius = 0.8
    shape.shape = capsule
    body.add_child(shape)
    add_child(body)
    if red_node == null:
        red_node = lie
    else:
        blue_node = lie

func _process(delta: float) -> void:
    if rotating:
        orbit += delta * (0.25 + Input.get_axis("ui_left", "ui_right"))
    if Input.is_action_just_pressed("ui_accept"):
        warm_light = not warm_light
        for node in [red_node, blue_node]:
            node.call("set_light_color", Color(1, 0.32, 0.1) if warm_light else Color(0.1, 0.4, 1))
    _position_camera()
    for node in [red_node, blue_node]:
        node.call("update_surface")
    readout.text = ("LIE-03 | RECONSTRUCTED DEPTH + Z-BUFFER\n"
        + "Front: %s / %d triangles\n" % [
            str(red_node.get("current_view_code")), int(red_node.get("current_triangle_count"))]
        + "Rear:  %s / %d triangles\n" % [
            str(blue_node.get("current_view_code")), int(blue_node.get("current_triangle_count"))]
        + "Arrows: orbit | Space: light | Actual source mesh: hidden")

func _position_camera() -> void:
    camera.position = Vector3(8.5 * sin(orbit), 3.0, 8.5 * cos(orbit) - 0.45)
    camera.look_at(Vector3(0, 1.4, -0.45), Vector3.UP)
