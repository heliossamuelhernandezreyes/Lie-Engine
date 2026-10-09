extends Node3D
## GPU compute proof is a separate Vulkan subproject; visible viewport uses
## four-source CPU reference with actual spatial reprojection for now.
const NodeScript = preload("res://scripts/lie_06_node.gd")
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
    _position_camera()
    node = NodeScript.new()
    node.name = "LieMultiView"
    node.set("automatically_update", false)
    add_child(node)
    var layer := CanvasLayer.new()
    add_child(layer)
    label = Label.new()
    label.position = Vector2(24,24)
    label.add_theme_font_size_override("font_size",20)
    layer.add_child(label)
    node.call("rebuild")

func _process(delta: float) -> void:
    azimuth += delta*Input.get_axis("ui_left","ui_right")*0.85
    _position_camera()
    if Input.is_action_just_pressed("ui_accept"):
        node.call("rebuild")
    label.text = ("LIE-06 | FOUR-VIEW CPU REFERENCE + VULKAN COMPUTE PROOF\n"
        + "Arrows move camera | Space reconstructs (slow CPU)\n"
        + "Sources: %s\n" % str(node.get("last_code"))
        + "Coverage %d | Triangles %d | CPU %.1f ms\n" % [
            int(node.get("coverage")),int(node.get("triangles")),
            float(node.get("last_build_time_usec"))/1000.0]
        + "Blender capture: %s | GPU test: separate gpu_compute project" %
            str(node.get("using_real_capture")))

func _position_camera() -> void:
    camera.position = Vector3(6*sin(azimuth),1.2,6*cos(azimuth))
    camera.look_at(Vector3.ZERO,Vector3.UP)
