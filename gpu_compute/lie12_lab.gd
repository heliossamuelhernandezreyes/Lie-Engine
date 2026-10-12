extends Node3D
const Transport=preload("res://lie11_light_effect.gd")
const Capture=preload("res://lie12_capture_effect.gd")
var lighting: CompositorEffect
var effect: CompositorEffect
var camera: Camera3D
var base_model: Dictionary
var model: Dictionary
var label: Label
var yaw_degrees: float=0.0
var distance_scale: float=1.0
var scenario_name: String="bounce"

func _ready() -> void:
    get_window().size=Vector2i(768,768)
    effect=Capture.new()
    base_model=effect.get("base_model")
    if base_model.is_empty():
        push_error("Generate captures/coded_shard with --coded-lighting before running LIE-12")
        return
    lighting=Transport.new()
    effect.set("lighting",lighting)
    set_scenario("bounce")
    var environment:=Environment.new()
    environment.background_mode=Environment.BG_COLOR
    environment.background_color=Color(.012,.018,.024)
    var world:=WorldEnvironment.new()
    world.environment=environment
    var compositor:=Compositor.new()
    compositor.compositor_effects=[lighting,effect]
    world.compositor=compositor
    add_child(world)
    camera=Camera3D.new()
    camera.fov=60
    camera.near=.1
    camera.far=100
    camera.current=true
    add_child(camera)
    move_camera()
    var layer:=CanvasLayer.new()
    label=Label.new()
    label.position=Vector2(14,14)
    label.add_theme_font_size_override("font_size",17)
    layer.add_child(label)
    add_child(layer)
    _update_label()

func set_scenario(name: String) -> void:
    scenario_name=name
    model=base_model.duplicate(true)
    model["bounces"]=0 if name=="direct" else 2
    if name=="absorbing":
        for key in model["materials"]:
            if "bounce red" in str(key): model["materials"][key]["absorption_code"]=980
    elif name=="moved": model["lights"][0]["position"]=[.8,.6,.5]
    elif name=="cool": model["lights"][0]["power_rgb"]=[7,17.5,35]
    elif name=="dark": model["lights"][0]["power_rgb"]=[0,0,0]
    lighting.call("configure",model)
    _update_label()

func _process(delta: float) -> void:
    if camera==null: return
    yaw_degrees+=Input.get_axis("ui_left","ui_right")*delta*35
    move_camera()
    var move:=Vector3.ZERO
    if Input.is_physical_key_pressed(KEY_W): move.z-=delta
    if Input.is_physical_key_pressed(KEY_S): move.z+=delta
    if Input.is_physical_key_pressed(KEY_A): move.x-=delta
    if Input.is_physical_key_pressed(KEY_D): move.x+=delta
    if move.length_squared()>0:
        var p: Array=model["lights"][0]["position"]
        model["lights"][0]["position"]=[float(p[0])+move.x,float(p[1]),float(p[2])+move.z]
        lighting.call("set_light_codes",model)

func move_camera() -> void:
    camera.position=effect.call("camera_position",yaw_degrees,distance_scale)
    camera.look_at(Vector3.ZERO)
    effect.call("set_view_yaw_degrees",yaw_degrees)
    effect.call("set_distance_scale",distance_scale)

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo: return
    match event.physical_keycode:
        KEY_B: set_scenario("direct" if scenario_name!="direct" else "bounce")
        KEY_X: set_scenario("absorbing" if scenario_name!="absorbing" else "bounce")
        KEY_C: set_scenario("cool" if scenario_name!="cool" else "bounce")
        KEY_O: set_scenario("dark" if scenario_name!="dark" else "bounce")

func _update_label() -> void:
    if label==null: return
    label.text="LIE-12 | Blender capture + grayscale / material codes\n"+scenario_name+" | arrows: camera, WASD: light, B: bounces, X: absorption, C: color"

func _exit_tree() -> void:
    # Remove the consumer before the producer's shared buffers and image.
    if effect!=null: effect.call("shutdown")
    if lighting!=null: lighting.call("shutdown")
