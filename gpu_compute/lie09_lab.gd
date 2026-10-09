extends Node3D
## LIE-09: Real Blender GLB -> opaque color/depth/normal capture -> GPU.
## Arrows orbit. Godot raster geometry can occlude or fall behind Lie.
const EffectScript = preload("res://lie09_blender_effect.gd")
var effect: CompositorEffect
var camera: Camera3D
var yaw_degrees := 0.0

func _ready() -> void:
    var world := WorldEnvironment.new()
    var sky := Environment.new()
    sky.background_mode = Environment.BG_COLOR
    sky.background_color = Color(0.025,0.055,0.11)
    world.environment = sky
    effect = EffectScript.new()
    var comp := Compositor.new()
    comp.compositor_effects = [effect]
    world.compositor = comp
    add_child(world)
    camera = Camera3D.new()
    camera.near = 0.1
    camera.far = 100.0
    camera.current = true
    camera.fov = 60.0
    add_child(camera)
    _move_camera()

func _process(delta: float) -> void:
    var axis: float = Input.get_axis("ui_left","ui_right")
    if absf(axis)>0.001:
        yaw_degrees = wrapf(yaw_degrees+axis*delta*52.0,0.0,360.0)
        _move_camera()

func _move_camera() -> void:
    var rad: float = deg_to_rad(yaw_degrees)
    var distance: float = float(effect.get("_capture_radius"))*3.5
    camera.position = Vector3(distance*sin(rad),0.0,distance*cos(rad))
    camera.look_at(Vector3.ZERO,Vector3.UP)
    effect.set_view_yaw_degrees(yaw_degrees)

func _exit_tree() -> void:
    if effect != null:
        effect.call("shutdown")
