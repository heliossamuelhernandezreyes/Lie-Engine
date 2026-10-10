extends Node3D
const Doc=preload("res://workshop/lie_face_document.gd")
const FaceEffect=preload("res://lie23_face_effect.gd")
var document:=Doc.new()
var effect: CompositorEffect
var camera: Camera3D
var picture: TextureRect
var texture: Texture2DRD
var ui: CanvasLayer
var controls: Dictionary={}
var status: Label
var stats: Label
var play_button: Button
var _connected: bool=false
var _poll_time: float=0
var _stats_time: float=0

func _ready() -> void:
    get_window().size=Vector2i(1280,800);effect=FaceEffect.new()
    var world:=WorldEnvironment.new();var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.015,.022,.035);world.environment=environment
    var compositor:=Compositor.new();compositor.compositor_effects=[effect];world.compositor=compositor;add_child(world)
    camera=Camera3D.new();camera.current=true;camera.fov=35;camera.near=.01;camera.far=5;add_child(camera)
    _build_ui();_apply();_refresh();DirAccess.make_dir_recursive_absolute("user://face23")
func _label(parent: Node,text: String,size: int=13) -> Label:
    var item:=Label.new();item.text=text;item.add_theme_font_size_override("font_size",size);parent.add_child(item);return item
func _button(parent: Node,text: String,callback: Callable) -> Button:
    var item:=Button.new();item.text=text;item.pressed.connect(callback);parent.add_child(item);return item
func _panel(position: Vector2) -> VBoxContainer:
    var panel:=PanelContainer.new();panel.position=position;panel.custom_minimum_size=Vector2(260,0)
    var style:=StyleBoxFlat.new();style.bg_color=Color(.035,.048,.071,.98)
    for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_content_margin(side,14)
    style.corner_radius_top_left=12;style.corner_radius_top_right=12;style.corner_radius_bottom_left=12;style.corner_radius_bottom_right=12
    panel.add_theme_stylebox_override("panel",style);ui.add_child(panel)
    var box:=VBoxContainer.new();box.add_theme_constant_override("separation",6);panel.add_child(box);return box
func _slider(parent: Node,key: String,title: String,step: float=.01) -> void:
    _label(parent,title);var item:=HSlider.new();item.min_value=Doc.LIMITS[key][0];item.max_value=Doc.LIMITS[key][1];item.step=step
    item.value_changed.connect(func(value: float):command({"op":"set_values","values":{key:value}}));parent.add_child(item);controls[key]=item
func _color(parent: Node,key: String,title: String) -> void:
    _label(parent,title);var item:=ColorPickerButton.new();item.custom_minimum_size=Vector2(215,30)
    item.color_changed.connect(func(c: Color):command({"op":"set_values","values":{key:[c.r,c.g,c.b]}}));parent.add_child(item);controls[key]=item
func _build_ui() -> void:
    ui=CanvasLayer.new();add_child(ui)
    var title:=Label.new();title.position=Vector2(24,18);title.text="LIE  ·  Rostro, mirada y parpadeo";title.add_theme_font_size_override("font_size",26);ui.add_child(title)
    picture=TextureRect.new();picture.position=Vector2(298,70);picture.size=Vector2(684,684);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;ui.add_child(picture)
    var left: VBoxContainer=_panel(Vector2(20,70));_label(left,"ROSTRO CAPTURADO").add_theme_color_override("font_color",Color(.35,.85,1))
    _label(left,"Lee Perry-Smith · Infinite-Realities\nCC BY 3.0 · órbitas y párpados nuevos",11)
    _slider(left,"head_yaw","Giro de cabeza")
    _slider(left,"blink","Cierre de párpados")
    _slider(left,"gaze_yaw","Mirada horizontal")
    _slider(left,"gaze_pitch","Mirada vertical")
    _slider(left,"pupil_radius","Radio pupilar · 0.8 a 3.2 mm",.00001)
    _color(left,"iris_color","Color del iris")
    var eyes:=HBoxContainer.new();left.add_child(eyes)
    _button(eyes,"Azul",func():command({"op":"set_values","values":{"iris_color":[.22,.57,.76]}}))
    _button(eyes,"Verde",func():command({"op":"set_values","values":{"iris_color":[.37,.62,.28]}}))
    _button(eyes,"Marrón",func():command({"op":"set_values","values":{"iris_color":[.40,.25,.13]}}))
    play_button=_button(left,"Animar mirada y parpadeo",func():command({"op":"set_playing","value":not document.state["playing"]}))
    var frames:=HBoxContainer.new();left.add_child(frames)
    for mode in ["bust","face","eyes"]:
        _button(frames,{"bust":"Busto","face":"Rostro","eyes":"Ojos"}[mode],func():command({"op":"set_values","values":{"framing":mode}}))
    var storage:=HBoxContainer.new();left.add_child(storage)
    _button(storage,"Guardar",func():command({"op":"save_document"}));_button(storage,"Abrir",func():command({"op":"load_document"}))
    var undo:=HBoxContainer.new();left.add_child(undo)
    _button(undo,"Deshacer",func():command({"op":"undo"}));_button(undo,"Rehacer",func():command({"op":"redo"}))
    _button(left,"Volver al taller",func():get_tree().change_scene_to_file("res://lie18_workshop.tscn"))
    var right: VBoxContainer=_panel(Vector2(1000,70));_label(right,"PIEL, CÁMARA Y LUZ").add_theme_color_override("font_color",Color(.35,.85,1))
    _color(right,"skin_tint","Tono de piel")
    var skin:=HBoxContainer.new();right.add_child(skin)
    _button(skin,"Original",func():command({"op":"set_values","values":{"skin_tint":[1,1,1]}}))
    _button(skin,"Tostada",func():command({"op":"set_values","values":{"skin_tint":[1,.82,.65]}}))
    _button(skin,"Oscura",func():command({"op":"set_values","values":{"skin_tint":[.55,.42,.32]}}))
    _slider(right,"camera_yaw","Órbita")
    _slider(right,"camera_elevation","Altura")
    _slider(right,"distance","Distancia")
    _slider(right,"light_azimuth","Dirección de luz")
    _slider(right,"light_power","Intensidad")
    _slider(right,"sss","Dispersión bajo la piel")
    _slider(right,"exposure","Exposición")
    status=_label(right,"Preparando capturas…",11);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.x=225
    stats=_label(right,"",11);stats.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;stats.custom_minimum_size.x=225
    var caption:=Label.new();caption.position=Vector2(310,756);caption.text="Ojos compartidos · párpados deformables · profundidad común · mallas invisibles";caption.add_theme_font_size_override("font_size",12);ui.add_child(caption)
func command(request: Variant) -> Dictionary:
    var r: Dictionary=document.dispatch(request)
    if r.get("ok",false):_apply();_refresh()
    if status!=null:status.text="Cambio aplicado · revisión %d"%document.revision if r.get("ok",false) else "No aplicado: "+str(r.get("error"))
    return r
func _refresh() -> void:
    for key in controls:
        var item: Variant=controls[key]
        if item is Range:item.set_value_no_signal(float(document.state[key]))
        elif item is ColorPickerButton:
            var c: Array=document.state[key];item.color=Color(c[0],c[1],c[2])
    play_button.text="Pausar animación" if document.state["playing"] else "Animar mirada y parpadeo"
func _apply() -> void:
    if camera==null or not effect.get("capture_loaded"):return
    var s: Dictionary=document.evaluated();var master: Dictionary=effect.get("master");var frame: String=s["framing"]
    var target:=Vector3(0,.23,0) if frame=="bust" else Vector3(0,.30,.02) if frame=="face" else Vector3(0,.29,.06)
    var distance: float=(.85 if frame=="bust" else .48 if frame=="face" else .30)*float(s["distance"])
    var yaw: float=deg_to_rad(s["camera_yaw"]);var el: float=deg_to_rad(s["camera_elevation"])
    camera.position=target+Vector3(sin(yaw)*cos(el),sin(el),cos(yaw)*cos(el))*distance;camera.look_at(target)
    var angle: float=deg_to_rad(s["light_azimuth"]);var light:=Vector3(sin(angle)*.42,.5,cos(angle)*.42);var shadow:=Transform3D(Basis.IDENTITY,light).looking_at(Vector3(0,.23,0),Vector3.UP)
    var p:=PackedFloat32Array()
    for v in [camera.position,camera.basis.x,camera.basis.y,-camera.basis.z]:p.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    p.append_array(PackedFloat32Array([tan(deg_to_rad(camera.fov)*.5),1,.01,5,0,.155,0,0]))
    var bytes: PackedByteArray=p.to_byte_array();bytes.append_array(PackedInt32Array([master["invocation_count"],master["vertex_count"],effect.get("render_size"),effect.get("render_size")]).to_byte_array())
    p=PackedFloat32Array([deg_to_rad(s["head_yaw"]),s["blink"],0,s["sss"],light.x,light.y,light.z,s["light_power"]])
    var c: Array=s["light_color"];p.append_array(PackedFloat32Array([c[0],c[1],c[2],0,.12,.14,.17,s["exposure"],1 if s["shadows"] else 0,s["roughness"],0,0]))
    for v in [shadow.basis.x,shadow.basis.y,-shadow.basis.z]:p.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    for key in ["skin_tint","iris_color"]:
        var a: Array=s[key];var color:=Color(a[0],a[1],a[2]).srgb_to_linear();p.append_array(PackedFloat32Array([color.r,color.g,color.b,s["pupil_radius"] if key=="iris_color" else 0]))
    p.append_array(PackedFloat32Array([deg_to_rad(s["gaze_yaw"]),deg_to_rad(s["gaze_pitch"]),master["face_sample_count"],master["eye_sample_count"]]))
    for a in master["anchors"]:p.append_array(PackedFloat32Array([a[0],a[1],a[2],master["eye_radius"]]))
    bytes.append_array(p.to_byte_array());effect.call("configure",bytes)
func agent_snapshot() -> Dictionary:
    var r: Dictionary=document.snapshot();r["capture_loaded"]=effect.get("capture_loaded");r["visible_source_meshes"]=0
    r["inbox"]=OS.get_user_data_dir()+"/face23/inbox.json";r["outbox"]=OS.get_user_data_dir()+"/face23/outbox.json"
    r["commands"]=["snapshot","set_values","set_playing","set_time","undo","redo","save_document","load_document"]
    r["shared_eyes"]=2;r["eye_library_copies"]=1;return r
func _poll_agent() -> void:
    var path: String="user://face23/inbox.json"
    if not FileAccess.file_exists(path):return
    var file:=FileAccess.open(path,FileAccess.READ)
    if file==null or file.get_length()>1024*1024:return
    var request: Variant=JSON.parse_string(file.get_as_text());file.close();DirAccess.remove_absolute(path)
    var id: Variant=request.get("request_id") if request is Dictionary else null
    var r: Dictionary=command(request.get("request") if request is Dictionary and request.has("request") else request)
    var output:=FileAccess.open("user://face23/outbox.json.tmp",FileAccess.WRITE)
    if output==null:return
    output.store_string(JSON.stringify({"request_id":id,"result":r,"snapshot":agent_snapshot()},"  ",true,true));output.close();DirAccess.rename_absolute("user://face23/outbox.json.tmp","user://face23/outbox.json")
func _process(delta: float) -> void:
    if document.state["playing"]:document.state["time"]=fposmod(float(document.state["time"])+delta,4);_apply()
    if effect!=null and effect.get("gpu_ready") and not _connected:texture=Texture2DRD.new();texture.texture_rd_rid=effect.get("output_rid");picture.texture=texture;_connected=true
    _poll_time+=delta
    if _poll_time>=.2:_poll_time=0;_poll_agent()
    _stats_time+=delta
    if _stats_time>=1:
        _stats_time=0
        if not effect.get("capture_loaded"):status.text=effect.get("failure")
        else:stats.text="Un ojo maestro · dos instancias\n%s muestras de piel y párpados\n%.1f MiB de buffers/texturas Lie\nMedición Android pendiente"%[str(effect.get("master")["face_sample_count"]),float(effect.get("allocation_bytes"))/1048576]
func _exit_tree() -> void:
    if texture!=null:texture.texture_rd_rid=RID()
    if effect!=null:effect.call("shutdown")
