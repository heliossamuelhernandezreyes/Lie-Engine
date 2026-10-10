extends Node3D
const Capture=preload("res://lie14_capture_effect.gd")
const Transport=preload("res://lie14_light_effect.gd")
const Rigid=preload("res://lie14_model.gd")
var effect: CompositorEffect
var lighting: CompositorEffect
var camera: Camera3D
var model: Dictionary={}
var poses: Array[Transform3D]=[]
var angles: Array=Rigid.BASE_ANGLES.duplicate()
var joints: Array[Node3D]=[]
var ui: CanvasLayer
var label: Label
var scenario_name: String="bounce"
var yaw_degrees: float=0
var elevation_degrees: float=12
var distance_scale: float=1
var playing: bool=false
var elapsed: float=0
var _suppress_slider: bool=false
var _sliders: Array[HSlider]=[]

func _ready() -> void:
    get_window().size=Vector2i(768,768)
    effect=Capture.new()
    if not bool(effect.get("capture_loaded")):
        push_error("LIE-14 requires captures/rigid_master/master.json")
        return
    lighting=Transport.new()
    effect.set("lighting",lighting)
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
    # Actual invisible hierarchy and rigid cylinder collision shapes.
    var parent: Node3D=self
    for i in range(3):
        var joint:=Node3D.new()
        joint.name="Joint_%d" % i
        joint.position=Vector3(-.65,-1,0) if i==0 else Vector3(0,1.2,0)
        parent.add_child(joint)
        joints.append(joint)
        var body:=StaticBody3D.new()
        body.name="InvisibleRigidPart_%d" % i
        body.position=Vector3(0,.6,0)
        joint.add_child(body)
        var collision:=CollisionShape3D.new()
        var shape:=CylinderShape3D.new()
        shape.radius=.18
        shape.height=1.2
        collision.shape=shape
        body.add_child(collision)
        parent=joint
    set_scenario("bounce")
    move_camera()
    _build_ui()

func set_scenario(name: String) -> void:
    scenario_name=name
    angles=(Rigid.MOVED_ANGLES if name=="pose" else Rigid.BASE_ANGLES).duplicate()
    apply_pose()

func apply_pose() -> void:
    poses=Rigid.skeleton(angles)
    if poses.size()!=3: return
    for i in range(3):
        joints[i].basis=Basis(Vector3.BACK,float(angles[i]))
        if i==2: joints[i].basis=joints[i].basis*Basis(Vector3.RIGHT,.3)
    model=Rigid.scene_model(effect.get("master"),scenario_name,angles)
    lighting.call("configure_rigid",model,poses)
    effect.call("set_poses",poses)
    _suppress_slider=true
    for i in range(_sliders.size()): _sliders[i].value=rad_to_deg(float(angles[i]))
    _suppress_slider=false
    if label!=null: label.text="LIE-14 | 1 maestro · 3 piezas · 36 vistas\n"+scenario_name+" | sprites + profundidad + normales"

func move_camera() -> void:
    if camera==null: return
    var yaw: float=deg_to_rad(yaw_degrees)
    var elevation: float=deg_to_rad(elevation_degrees)
    var target:=Vector3(0,.5,0)
    camera.position=target+Vector3(sin(yaw)*cos(elevation),sin(elevation),cos(yaw)*cos(elevation))*5.8*distance_scale
    camera.look_at(target)

func _process(delta: float) -> void:
    if camera==null: return
    yaw_degrees+=Input.get_axis("ui_left","ui_right")*delta*35
    elevation_degrees=clampf(elevation_degrees+Input.get_axis("ui_down","ui_up")*delta*25,-75,75)
    move_camera()
    if playing:
        elapsed+=delta
        angles=[-.55+.3*sin(elapsed),1.2+.4*sin(elapsed*.8),-.7+.35*cos(elapsed*.7)]
        apply_pose()

func _build_ui() -> void:
    ui=CanvasLayer.new()
    add_child(ui)
    var panel:=VBoxContainer.new()
    panel.position=Vector2(16,16)
    panel.custom_minimum_size=Vector2(330,0)
    ui.add_child(panel)
    label=Label.new()
    label.add_theme_font_size_override("font_size",16)
    panel.add_child(label)
    for i in range(3):
        var slider:=HSlider.new()
        slider.min_value=-120
        slider.max_value=120
        slider.step=.5
        slider.custom_minimum_size=Vector2(320,26)
        slider.value=rad_to_deg(float(angles[i]))
        slider.value_changed.connect(func(value: float):
            if _suppress_slider: return
            playing=false
            angles[i]=deg_to_rad(value)
            apply_pose())
        panel.add_child(slider)
        _sliders.append(slider)
    var row:=HBoxContainer.new()
    panel.add_child(row)
    for item in [["Mover","play"],["Otra pose","pose"],["Luz","light"],["Absorción","absorbing"]]:
        var button:=Button.new()
        button.text=item[0]
        var action: String=item[1]
        button.pressed.connect(func():
            if action=="play": playing=not playing
            else:
                playing=false
                set_scenario(action))
        row.add_child(button)
    var check:=CheckButton.new()
    check.text="Normales por píxel"
    check.button_pressed=true
    check.toggled.connect(func(value: bool): effect.call("set_detailed_normals",value))
    panel.add_child(check)
    var orbit:=HSlider.new()
    orbit.min_value=-180
    orbit.max_value=180
    orbit.custom_minimum_size=Vector2(320,24)
    orbit.value_changed.connect(func(value: float): yaw_degrees=value; move_camera())
    panel.add_child(orbit)
    label.text="LIE-14 | 1 maestro · 3 piezas · 36 vistas\nArrastra articulaciones y cámara"

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo: return
    match event.physical_keycode:
        KEY_SPACE: playing=not playing
        KEY_P: set_scenario("pose" if scenario_name!="pose" else "bounce")
        KEY_L: set_scenario("light" if scenario_name!="light" else "bounce")
        KEY_X: set_scenario("absorbing" if scenario_name!="absorbing" else "bounce")
        KEY_B: set_scenario("direct" if scenario_name!="direct" else "bounce")
        KEY_N: effect.call("set_detailed_normals",not bool(effect.get("detailed_normals")))

func _exit_tree() -> void:
    if effect!=null: effect.call("shutdown")
    if lighting!=null: lighting.call("shutdown")
