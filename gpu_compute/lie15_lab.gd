extends Node3D
const Capture=preload("res://lie15_capture_effect.gd")
const Transport=preload("res://lie15_light_effect.gd")
const Rigid=preload("res://lie15_model.gd")
const PARENTS: Array=[-1,0,0,0,3,0,5,2,7,8,2,10,11,1,1]
var effect: CompositorEffect
var lighting: CompositorEffect
var camera: Camera3D
var model: Dictionary={}
var poses: Array[Transform3D]=[]
var joints: Array[Node3D]=[]
var bodies: Array[StaticBody3D]=[]
var ui: CanvasLayer
var label: Label
var scenario_name: String="bounce"
var yaw_degrees: float=24
var elevation_degrees: float=10
var distance_scale: float=1
var playing: bool=false
var elapsed: float=0
var reference_root: Node3D
var world: WorldEnvironment
var _dragging: bool=false

func _ready() -> void:
    get_window().size=Vector2i(768,768)
    effect=Capture.new()
    if not bool(effect.get("capture_loaded")):
        push_error("LIE-15 requires captures/robot_master/master.json")
        return
    lighting=Transport.new()
    effect.set("lighting",lighting)
    var environment:=Environment.new()
    environment.background_mode=Environment.BG_COLOR
    environment.background_color=Color(.012,.018,.024)
    environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color=Color(.3,.4,.5)
    environment.ambient_light_energy=.5
    world=WorldEnvironment.new()
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
    for i in range(Rigid.PARTS):
        var joint:=Node3D.new()
        joint.name="Joint_%02d" % i
        (self if int(PARENTS[i])<0 else joints[int(PARENTS[i])]).add_child(joint)
        joints.append(joint)
        var body:=StaticBody3D.new()
        body.name="InvisiblePart_%02d" % i
        joint.add_child(body)
        bodies.append(body)
        var collision:=CollisionShape3D.new()
        collision.shape=BoxShape3D.new()
        body.add_child(collision)
    set_scenario("bounce")
    move_camera()
    _build_ui()

func set_scenario(name: String) -> void:
    scenario_name=name
    elapsed=0
    apply_pose()

func apply_pose() -> void:
    poses=Rigid.skeleton(elapsed,scenario_name=="pose")
    if poses.size()!=Rigid.PARTS: return
    for i in range(Rigid.PARTS):
        var rotation: Basis=poses[i].basis.orthonormalized()
        var scale: Vector3=poses[i].basis.get_scale()
        var pivot: Vector3=poses[i].origin
        if i in [3,4,5,6,7,8,10,11]: pivot+=rotation*Vector3(0,scale.y*.5,0)
        elif i in [9,12]: pivot-=rotation*Vector3(0,-.01,.1)
        elif i>=13: pivot=poses[1].origin
        joints[i].global_transform=Transform3D(rotation,pivot)
        bodies[i].global_transform=Transform3D(rotation,poses[i].origin)
        ((bodies[i].get_child(0) as CollisionShape3D).shape as BoxShape3D).size=scale
    model=Rigid.scene_model(effect.get("master"),scenario_name,elapsed)
    lighting.call("configure_rigid",model,poses)
    effect.call("set_poses",poses)
    if reference_root!=null:
        for i in range(Rigid.PARTS): (reference_root.get_child(i) as Node3D).transform=poses[i]
    if label!=null: label.text="LIE · robot de Arcont\n1 maestro · 15 piezas · "+scenario_name

func move_camera() -> void:
    if camera==null: return
    var yaw: float=deg_to_rad(yaw_degrees)
    var elevation: float=deg_to_rad(elevation_degrees)
    var target:=Vector3(0,.25,0)
    camera.position=target+Vector3(sin(yaw)*cos(elevation),sin(elevation),cos(yaw)*cos(elevation))*3.6*distance_scale
    camera.look_at(target)

func _process(delta: float) -> void:
    if camera==null: return
    yaw_degrees+=Input.get_axis("ui_left","ui_right")*delta*35
    elevation_degrees=clampf(elevation_degrees+Input.get_axis("ui_down","ui_up")*delta*25,-75,75)
    move_camera()
    if playing:
        elapsed+=delta
        apply_pose()

func set_reference(value: bool) -> void:
    effect.enabled=not value
    lighting.enabled=not value
    if reference_root!=null:
        remove_child(reference_root)
        reference_root.queue_free()
        reference_root=null
    if not value: return
    reference_root=Node3D.new()
    reference_root.name="Separate3DGeometryReference"
    add_child(reference_root)
    var source: PackedScene=load("res://assets/lie15/master-neutral.glb")
    for i in range(Rigid.PARTS):
        var instance: Node3D=source.instantiate()
        reference_root.add_child(instance)
        instance.transform=poses[i]
        _reference_materials(instance,i)
    for light in model["lights"]:
        var lamp:=OmniLight3D.new()
        lamp.position=Rigid.Model.vector(light["position"])
        lamp.light_color=Color(.9,.95,1)
        lamp.light_energy=3
        lamp.omni_range=7
        reference_root.add_child(lamp)
    # Reference uses Godot native PBR; it is a geometry inspection aid, not
    # an equivalent implementation of Lie's bounded transport approximation.

func _reference_materials(node: Node,i: int) -> void:
    if node is MeshInstance3D:
        var m:=StandardMaterial3D.new()
        var p: Dictionary=model["surface_materials"][Rigid.material_name(i)]
        var tint: Vector3=Rigid.Model.vector(p["tint_linear"])
        m.albedo_color=Color(tint.x,tint.y,tint.z)
        m.metallic=float(p["metallic"])
        m.roughness=float(p["roughness"])
        if float(p["emission"])>0:
            m.emission_enabled=true
            m.emission=m.albedo_color
        (node as MeshInstance3D).material_override=m
    for child in node.get_children(): _reference_materials(child,i)

func _build_ui() -> void:
    ui=CanvasLayer.new()
    add_child(ui)
    var panel:=VBoxContainer.new()
    panel.position=Vector2(16,16)
    panel.custom_minimum_size=Vector2(320,0)
    ui.add_child(panel)
    label=Label.new()
    label.add_theme_font_size_override("font_size",18)
    label.text="LIE · robot de Arcont\n1 maestro · 15 piezas · sprites"
    panel.add_child(label)
    var row:=HBoxContainer.new()
    panel.add_child(row)
    for item in [["Animar","play"],["Pose","pose"],["Luz","light"],["Rebote","direct"]]:
        var button:=Button.new()
        button.text=item[0]
        var action: String=item[1]
        button.pressed.connect(func():
            if action=="play": playing=not playing
            else: playing=false; set_scenario("bounce" if scenario_name==action else action))
        row.add_child(button)
    _slider(panel,"Órbita",-180,180,yaw_degrees,func(v: float): yaw_degrees=v; move_camera())
    _slider(panel,"Altura",-75,75,elevation_degrees,func(v: float): elevation_degrees=v; move_camera())
    _slider(panel,"Distancia",.65,2,distance_scale,func(v: float): distance_scale=v; move_camera())
    _slider(panel,"Articulación",0,TAU,elapsed,func(v: float): playing=false; elapsed=v; apply_pose())
    var ref:=CheckButton.new()
    ref.text="Inspeccionar malla 3D de referencia"
    ref.toggled.connect(set_reference)
    panel.add_child(ref)
    var hint:=Label.new()
    hint.text="Arrastra la cámara · rueda para acercar\nEspacio: animar · flechas: cámara"
    panel.add_child(hint)

func _slider(parent: Node,text: String,minimum: float,maximum: float,value: float,callback: Callable) -> void:
    var title:=Label.new()
    title.text=text
    parent.add_child(title)
    var slider:=HSlider.new()
    slider.min_value=minimum
    slider.max_value=maximum
    slider.step=.01
    slider.value=value
    slider.custom_minimum_size=Vector2(300,22)
    slider.value_changed.connect(callback)
    parent.add_child(slider)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_SPACE: playing=not playing
    if event is InputEventMouseButton:
        if event.button_index==MOUSE_BUTTON_LEFT: _dragging=event.pressed
        if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
            distance_scale=clampf(distance_scale*(.9 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.1),.65,2)
            move_camera()
    if event is InputEventMouseMotion and _dragging:
        yaw_degrees-=event.relative.x*.3
        elevation_degrees=clampf(elevation_degrees+event.relative.y*.3,-75,75)
        move_camera()

func _exit_tree() -> void:
    if effect!=null: effect.call("shutdown")
    if lighting!=null: lighting.call("shutdown")
