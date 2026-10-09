extends Node3D
## LIE-05 manual research lab: the camera may orbit freely in 3D.
## Rebuild on Space; no continuous 60FPS claim for CPU forward reprojection.
const NodeScript = preload("res://scripts/lie_reprojection_node.gd")

var camera: Camera3D
var node: Node3D
var label: Label
var azimuth := PI / 4.0

func _ready() -> void:
    var environment := WorldEnvironment.new()
    var settings := Environment.new()
    settings.background_mode = Environment.BG_COLOR
    settings.background_color = Color("#0a1726")
    environment.environment = settings
    add_child(environment)

    camera = Camera3D.new()
    camera.name = "LieCamera"
    camera.current = true
    camera.fov = 50.0
    add_child(camera)
    camera.position = Vector3(6.0 * sin(azimuth), 1.2, 6.0 * cos(azimuth))
    camera.look_at(Vector3.ZERO, Vector3.UP)

    node = NodeScript.new()
    node.name = "LieNovelView"
    node.set("automatically_update", false)
    add_child(node)

    var layer := CanvasLayer.new()
    add_child(layer)
    label = Label.new()
    label.position = Vector2(24, 24)
    label.add_theme_font_size_override("font_size", 20)
    layer.add_child(label)
    node.call("rebuild")
    _display()

func _process(delta: float) -> void:
    azimuth += delta * Input.get_axis("ui_left", "ui_right") * 0.85
    camera.position = Vector3(6.0 * sin(azimuth), 1.2, 6.0 * cos(azimuth))
    camera.look_at(Vector3.ZERO, Vector3.UP)
    if Input.is_action_just_pressed("ui_accept"):
        node.call("rebuild")
    _display()

func _display() -> void:
    label.text = ("LIE-05 | CPU DEPTH REPROJECTION EXPERIMENT\n"
        + "Arrows: move camera | Space: rebuild new view\n"
        + "Sources: %s\n" % str(node.get("last_code"))
        + "Mesh: %d tris | coverage: %d cells\n" % [
            int(node.get("triangles")), int(node.get("coverage"))]
        + "Last CPU build: %.1f ms | Real Blender input: %s\n" % [
            float(node.get("last_build_time_usec")) / 1000.0,
            str(node.get("using_real_capture"))]
        + "NOT continuous mobile rendering; capture and benchmark first.")
