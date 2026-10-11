extends Node3D
const Effect=preload("res://lie25_anatomy_effect.gd")
var effect: CompositorEffect
var camera: Camera3D
var texture: Texture2DRD
var picture: TextureRect
var status: Label
var state: Dictionary={"mask":15,"camera_yaw":0.0,"object_yaw":0.0,"light_azimuth":-35.0,"light_power":4.0,"distance":.95,"unlit":false,"shadows":true,
    "palette":[[.52,.29,.18],[.32,.045,.028],[.72,.64,.47],[.29,.12,.15]],"light_color":[1.0,.88,.76]}
var revision: int=0
var controls: Dictionary={}
var connected: bool=false
const LIMITS={"camera_yaw":[-180,180],"object_yaw":[-90,90],"light_azimuth":[-180,180],"light_power":[0,15],"distance":[.65,1.8]}

func _ready() -> void:
    get_window().size=Vector2i(1280,800)
    effect=Effect.new(512,2)
    var world:=WorldEnvironment.new();var environment:=Environment.new()
    environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.018,.023,.03);world.environment=environment
    var compositor:=Compositor.new();compositor.compositor_effects=[effect];world.compositor=compositor;add_child(world)
    camera=Camera3D.new();camera.current=true;camera.fov=35;camera.near=.01;camera.far=5;add_child(camera)
    var ui:=CanvasLayer.new();add_child(ui)
    var title:=Label.new();title.text="LIE  ·  Anatomía por capas";title.position=Vector2(24,18);title.add_theme_font_size_override("font_size",26);ui.add_child(title)
    picture=TextureRect.new();picture.position=Vector2(330,70);picture.size=Vector2(684,684);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
    picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;ui.add_child(picture)
    var scroll:=ScrollContainer.new();scroll.position=Vector2(24,72);scroll.size=Vector2(290,684);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;ui.add_child(scroll)
    var box:=VBoxContainer.new();box.custom_minimum_size.x=276;box.add_theme_constant_override("separation",9);scroll.add_child(box)
    var credit:=Label.new();credit.text="3DAnatomyman · Always3D / DBCLS\nCC BY-SA 2.1 JP\nBusto capturado · giro rígido";credit.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;credit.custom_minimum_size.x=276;box.add_child(credit)
    for id in range(4):
        var row:=HBoxContainer.new();box.add_child(row)
        var toggle:=CheckBox.new();toggle.text=["Piel","Músculos","Huesos","Interiores"][id];toggle.button_pressed=true;toggle.custom_minimum_size.x=170;row.add_child(toggle)
        toggle.toggled.connect(func(on: bool):command({"op":"set_values","values":{"mask":int(state["mask"])|(1<<id) if on else int(state["mask"])&~(1<<id)}}))
        controls["layer%d"%id]=toggle
        var picker:=ColorPickerButton.new();var c: Array=state["palette"][id];picker.color=Color(c[0],c[1],c[2]).linear_to_srgb();picker.custom_minimum_size=Vector2(65,32);row.add_child(picker);controls["color%d"%id]=picker
        picker.color_changed.connect(func(color: Color):
            var palette: Array=state["palette"].duplicate(true);var linear:=color.srgb_to_linear();palette[id]=[linear.r,linear.g,linear.b]
            command({"op":"set_values","values":{"palette":palette}}))
    for key in LIMITS:
        var label:=Label.new();label.text={"camera_yaw":"Órbita","object_yaw":"Giro rígido","light_azimuth":"Dirección de luz","light_power":"Potencia","distance":"Distancia"}[key];box.add_child(label)
        var slider:=HSlider.new();slider.min_value=LIMITS[key][0];slider.max_value=LIMITS[key][1];slider.step=.01;slider.value=state[key];box.add_child(slider)
        slider.value_changed.connect(func(value: float):command({"op":"set_values","values":{key:value}}));controls[key]=slider
    status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.x=276;box.add_child(status)
    var limit:=Label.new();limit.text="Sin rig corporal ni expresiones faciales.\nColores de prueba; sin texturas de piel.\nSombras desde muestras capturadas.";limit.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(limit)
    var back:=Button.new();back.text="Volver al taller";back.pressed.connect(func():get_tree().change_scene_to_file("res://lie18_workshop.tscn"));box.add_child(back)
    _apply()

func command(request: Variant) -> Dictionary:
    if not request is Dictionary:return {"ok":false,"error":"request"}
    if request.get("op")=="snapshot":return {"ok":true,"revision":revision,"state":state.duplicate(true)}
    if request.get("op")!="set_values" or not request.get("values") is Dictionary:return {"ok":false,"error":"operation"}
    if request.has("expected_revision") and request["expected_revision"]!=revision:return {"ok":false,"error":"stale revision"}
    var next: Dictionary=state.duplicate(true)
    for key in request["values"]:
        var value: Variant=request["values"][key]
        if key in LIMITS:
            if not (value is int or value is float) or not is_finite(float(value)) or value<LIMITS[key][0] or value>LIMITS[key][1]:return {"ok":false,"error":"range"}
        elif key=="mask":
            if not (value is int or value is float) or not is_finite(float(value)) or value!=floorf(value) or value<0 or value>15:return {"ok":false,"error":"mask"}
        elif key in ["unlit","shadows"]:
            if not value is bool:return {"ok":false,"error":"boolean"}
        elif key in ["palette","light_color"]:
            var colors: Array=value if key=="palette" and value is Array else [value]
            if key=="palette" and colors.size()!=4:return {"ok":false,"error":"palette"}
            for color in colors:
                if not color is Array or color.size()!=3:return {"ok":false,"error":"color"}
                for component in color:
                    if not (component is int or component is float) or not is_finite(float(component)) or component<0 or component>1:return {"ok":false,"error":"color"}
        else:return {"ok":false,"error":"unknown field"}
        next[key]=value
    state=next;revision+=1;_apply()
    for key in LIMITS:
        if controls.has(key):controls[key].set_value_no_signal(float(state[key]))
    for id in range(4):
        if controls.has("layer%d"%id):controls["layer%d"%id].set_pressed_no_signal(int(state["mask"])&(1<<id)!=0)
        if controls.has("color%d"%id):
            var pigment: Array=state["palette"][id];controls["color%d"%id].color=Color(pigment[0],pigment[1],pigment[2]).linear_to_srgb()
    return {"ok":true,"revision":revision}

func _apply() -> void:
    if camera==null or not effect.get("capture_loaded"):return
    var yaw: float=deg_to_rad(float(state["camera_yaw"]));camera.position=Vector3(sin(yaw),0,cos(yaw))*float(state["distance"]);camera.look_at(Vector3.ZERO)
    var angle: float=deg_to_rad(float(state["light_azimuth"]));var light:=Vector3(sin(angle)*.42,.34,cos(angle)*.42)
    var shadow:=Transform3D(Basis.IDENTITY,light).looking_at(Vector3.ZERO,Vector3.UP)
    var floats:=PackedFloat32Array()
    for v in [camera.position,camera.basis.x,camera.basis.y,-camera.basis.z]:floats.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    floats.append_array(PackedFloat32Array([tan(deg_to_rad(camera.fov)*.5),1,.01,5,0,0,0,0]))
    var bytes: PackedByteArray=floats.to_byte_array();var master: Dictionary=effect.get("master");var count: int=int(master["sample_count"])
    bytes.append_array(PackedInt32Array([count,8,effect.get("render_size"),effect.get("render_size")]).to_byte_array())
    floats=PackedFloat32Array([deg_to_rad(float(state["object_yaw"])),0,state["mask"],0,light.x,light.y,light.z,state["light_power"]])
    var c: Array=state["light_color"];floats.append_array(PackedFloat32Array([c[0],c[1],c[2],0,.12,.14,.17,1,1 if state["shadows"] else 0,1,1 if state["unlit"] else 0,0]))
    for v in [shadow.basis.x,shadow.basis.y,-shadow.basis.z]:floats.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    c=state["palette"][0];floats.append_array(PackedFloat32Array([c[0],c[1],c[2],0,0,0,count,0]))
    for id in range(1,4):
        c=state["palette"][id];floats.append_array(PackedFloat32Array([c[0],c[1],c[2],0]))
    bytes.append_array(floats.to_byte_array())
    if not effect.call("configure",bytes):status.text="Paquete rechazado"

func _process(_delta: float) -> void:
    if effect.get("gpu_ready") and not connected:
        texture=Texture2DRD.new();texture.texture_rd_rid=effect.get("output_rid");picture.texture=texture;connected=true
    status.text=effect.get("failure") if not str(effect.get("failure")).is_empty() else "%s muestras · %.1f MiB Lie\nOriginal 671.2 MiB · 934 piezas\nGPU/Android físico pendiente"%[str(int(effect.get("master").get("sample_count",0))),float(effect.get("allocation_bytes"))/1048576]

func _exit_tree() -> void:
    if texture!=null:texture.texture_rd_rid=RID()
    if effect!=null:effect.call("shutdown")
