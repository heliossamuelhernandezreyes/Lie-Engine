extends Node3D
const HumanDocument=preload("res://workshop/lie_human_document.gd")
const HumanEffect=preload("res://lie20_human_effect.gd")
var document:=HumanDocument.new()
var effect: CompositorEffect
var camera: Camera3D
var picture: TextureRect
var texture: Texture2DRD
var controls: Dictionary={}
var status: Label
var stats: Label
var play_button: Button
var _poll_time: float=0
var _stats_time: float=0
var _texture_connected: bool=false

func _ready() -> void:
    get_window().size=Vector2i(1280,800)
    effect=HumanEffect.new(512)
    var world:=WorldEnvironment.new();var environment:=Environment.new()
    environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.015,.022,.033);world.environment=environment
    var compositor:=Compositor.new();compositor.compositor_effects=[effect];world.compositor=compositor;add_child(world)
    camera=Camera3D.new();camera.current=true;camera.fov=35;camera.near=.01;camera.far=5;add_child(camera)
    _build_ui();_apply();DirAccess.make_dir_recursive_absolute("user://human")

func _label(parent: Node,text: String,size: int=14) -> Label:
    var label:=Label.new();label.text=text;label.add_theme_font_size_override("font_size",size);parent.add_child(label);return label

func _button(parent: Node,text: String,callback: Callable) -> Button:
    var button:=Button.new();button.text=text;button.pressed.connect(callback);parent.add_child(button);return button

func _panel(ui: Node,position: Vector2,width: float) -> VBoxContainer:
    var panel:=PanelContainer.new();panel.position=position;panel.custom_minimum_size=Vector2(width,0)
    var style:=StyleBoxFlat.new();style.bg_color=Color(.035,.048,.071,.98)
    for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: style.set_content_margin(side,14)
    style.corner_radius_top_left=12;style.corner_radius_top_right=12;style.corner_radius_bottom_left=12;style.corner_radius_bottom_right=12
    panel.add_theme_stylebox_override("panel",style);ui.add_child(panel)
    var box:=VBoxContainer.new();box.add_theme_constant_override("separation",8);panel.add_child(box);return box

func _slider(parent: Node,key: String,title: String) -> void:
    _label(parent,title,13)
    var slider:=HSlider.new();slider.min_value=HumanDocument.LIMITS[key][0];slider.max_value=HumanDocument.LIMITS[key][1];slider.step=.01
    slider.value=document.state[key];slider.custom_minimum_size=Vector2(200,24)
    slider.value_changed.connect(func(value: float): command({"op":"set_values","values":{key:value}}));parent.add_child(slider);controls[key]=slider

func _build_ui() -> void:
    var ui:=CanvasLayer.new();add_child(ui)
    var title:=Label.new();title.position=Vector2(24,18);title.text="LIE  ·  Taller de maestros humanos";title.add_theme_font_size_override("font_size",26);ui.add_child(title)
    picture=TextureRect.new();picture.position=Vector2(298,70);picture.size=Vector2(684,684);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
    picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.add_child(picture)
    var left: VBoxContainer=_panel(ui,Vector2(20,70),260)
    _label(left,"MAESTRO CAPTURADO",13).add_theme_color_override("font_color",Color(.35,.85,1))
    _label(left,"Lee Perry-Smith",21);_label(left,"Escaneo · Infinite-Realities\nCC BY 3.0 · preparación en Blender",12)
    _slider(left,"head_yaw","Giro de cabeza")
    _slider(left,"lid_squeeze","Correctivo de párpados cerrados")
    _slider(left,"jaw_drop","Correctivo de mandíbula")
    play_button=_button(left,"Reproducir movimiento",func(): command({"op":"set_playing","value":not document.state["playing"]}))
    var storage:=HBoxContainer.new();left.add_child(storage)
    _button(storage,"Guardar",func(): command({"op":"save_document"}));_button(storage,"Abrir",func(): command({"op":"load_document"}))
    var undo:=HBoxContainer.new();left.add_child(undo)
    _button(undo,"Deshacer",func(): command({"op":"undo"}));_button(undo,"Rehacer",func(): command({"op":"redo"}))
    _label(left,"CAMARA",12)
    _slider(left,"camera_yaw","Órbita")
    _slider(left,"camera_elevation","Altura")
    _slider(left,"distance","Distancia")
    _button(left,"Volver al ensamblaje",func(): get_tree().change_scene_to_file("res://lie18_workshop.tscn"))
    var right: VBoxContainer=_panel(ui,Vector2(1000,70),260)
    _label(right,"PIEL E ILUMINACIÓN",13).add_theme_color_override("font_color",Color(.35,.85,1))
    _slider(right,"light_azimuth","Dirección de la luz")
    _slider(right,"light_power","Intensidad")
    _slider(right,"sss","Dispersión bajo la piel")
    _slider(right,"roughness","Rugosidad")
    _slider(right,"exposure","Exposición")
    var shadow:=CheckBox.new();shadow.text="Sombras desde las capturas";shadow.button_pressed=true;right.add_child(shadow)
    shadow.toggled.connect(func(value: bool): command({"op":"set_values","values":{"shadows":value}}));controls["shadows"]=shadow
    var presets:=HBoxContainer.new();right.add_child(presets)
    _button(presets,"Cálida",func(): command({"op":"set_values","values":{"light_color":[1,.87,.74]}}))
    _button(presets,"Fría",func(): command({"op":"set_values","values":{"light_color":[.62,.78,1]}}))
    status=_label(right,"Preparando capturas…",12);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.x=225
    _label(right,"Escaneo con ojos cerrados.\nSin cabello ni interior de boca.\nCorrectivos faciales experimentales.",12)
    stats=_label(right,"",11);stats.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;stats.custom_minimum_size.x=225
    var caption:=Label.new();caption.position=Vector2(310,755);caption.text="Apariencia capturada · superficie de deformación invisible";ui.add_child(caption)

func command(request: Variant) -> Dictionary:
    var result: Dictionary=document.dispatch(request)
    if result.get("ok",false):
        _apply();_refresh()
    if status!=null: status.text="Cambio aplicado · revisión %d" % document.revision if result.get("ok",false) else "No aplicado: "+str(result.get("error"))
    return result

func _refresh() -> void:
    for key in controls:
        if controls[key] is Range: controls[key].set_value_no_signal(float(document.state[key]))
        elif controls[key] is CheckBox: controls[key].set_pressed_no_signal(document.state[key])
    if play_button!=null: play_button.text="Pausar movimiento" if document.state["playing"] else "Reproducir movimiento"

func _apply() -> void:
    if camera==null or not effect.get("capture_loaded"): return
    var state: Dictionary=document.evaluated();var target:=Vector3(0,.23,0)
    var yaw: float=deg_to_rad(float(state["camera_yaw"]));var elevation: float=deg_to_rad(float(state["camera_elevation"]))
    camera.position=target+Vector3(sin(yaw)*cos(elevation),sin(elevation),cos(yaw)*cos(elevation))*float(state["distance"]);camera.look_at(target)
    var angle: float=deg_to_rad(float(state["light_azimuth"]));var light:=Vector3(sin(angle)*.42,.5,cos(angle)*.42)
    var shadow_pose:=Transform3D(Basis.IDENTITY,light).looking_at(target,Vector3.UP)
    var packet:=PackedFloat32Array()
    for v in [camera.position,camera.basis.x,camera.basis.y,-camera.basis.z]: packet.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    packet.append_array(PackedFloat32Array([tan(deg_to_rad(camera.fov)*.5),1,.01,5]))
    packet.append_array(PackedFloat32Array([0,.155,0,0]))
    var bytes: PackedByteArray=packet.to_byte_array();var master: Dictionary=effect.get("master")
    bytes.append_array(PackedInt32Array([int(master["sample_count"]),int(master["vertex_count"]),int(effect.get("render_size")),int(effect.get("render_size"))]).to_byte_array())
    var settings:=PackedFloat32Array([deg_to_rad(float(state["head_yaw"])),state["lid_squeeze"],state["jaw_drop"],state["sss"],light.x,light.y,light.z,state["light_power"]])
    var color: Array=state["light_color"];settings.append_array(PackedFloat32Array([color[0],color[1],color[2],0,.12,.14,.17,state["exposure"],1 if state["shadows"] else 0,state["roughness"],0,0]))
    for v in [shadow_pose.basis.x,shadow_pose.basis.y,-shadow_pose.basis.z]: settings.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    bytes.append_array(settings.to_byte_array());effect.call("configure",bytes)

func agent_snapshot() -> Dictionary:
    var result: Dictionary=document.snapshot();result["capture_loaded"]=effect.get("capture_loaded") if effect!=null else false
    result["visible_source_meshes"]=0;result["inbox"]=OS.get_user_data_dir()+"/human/inbox.json";result["outbox"]=OS.get_user_data_dir()+"/human/outbox.json"
    result["commands"]=["snapshot","set_values","set_playing","set_time","save_document","load_document","undo","redo"]
    return result

func _poll_agent() -> void:
    var path: String="user://human/inbox.json"
    if not FileAccess.file_exists(path): return
    var file:=FileAccess.open(path,FileAccess.READ)
    if file==null or file.get_length()>1024*1024: return
    var request: Variant=JSON.parse_string(file.get_as_text());file.close();DirAccess.remove_absolute(path)
    var id: Variant=request.get("request_id") if request is Dictionary else null
    var result: Dictionary=command(request.get("request") if request is Dictionary and request.has("request") else request)
    var output:=FileAccess.open("user://human/outbox.json.tmp",FileAccess.WRITE)
    if output==null: return
    output.store_string(JSON.stringify({"request_id":id,"result":result,"snapshot":agent_snapshot()},"  ",true,true));output.close()
    DirAccess.rename_absolute("user://human/outbox.json.tmp","user://human/outbox.json")

func _process(delta: float) -> void:
    if document.state["playing"]:
        document.state["time"]=fposmod(float(document.state["time"])+delta,4);_apply()
    if effect!=null and effect.get("gpu_ready") and not _texture_connected:
        texture=Texture2DRD.new();texture.texture_rd_rid=effect.get("output_rid");picture.texture=texture;_texture_connected=true
    _poll_time+=delta
    if _poll_time>=.2: _poll_time=0;_poll_agent()
    _stats_time+=delta
    if _stats_time>=1 and stats!=null:
        _stats_time=0
        if not effect.get("capture_loaded"): status.text=effect.get("failure")
        else: stats.text="%s muestras compartidas\n%.1f MiB de buffers Lie\nMedición Android pendiente" % [str(effect.get("master")["sample_count"]),float(effect.get("allocation_bytes"))/1048576]

func _exit_tree() -> void:
    if texture!=null: texture.texture_rd_rid=RID()
    if effect!=null: effect.call("shutdown")
