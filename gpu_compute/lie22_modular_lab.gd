extends Node3D
const Doc=preload("res://workshop/lie_modular_document.gd")
const Effect=preload("res://lie22_modular_effect.gd")
const MAX_FRAGMENTS=32
var document:=Doc.new()
var effect: CompositorEffect
var camera: Camera3D
var picture: TextureRect
var texture: Texture2DRD
var ui: CanvasLayer
var controls: Dictionary={}
var eye_controls: VBoxContainer
var wall_controls: VBoxContainer
var status: Label
var stats: Label
var cell_control: SpinBox
var _connected: bool=false
var _bodies: Dictionary={}
var _statics: Dictionary={}
var _damage_key: String=""
var _poll_time: float=0
var _stats_time: float=0
var _runtime_stats: Dictionary={}

func _ready() -> void:
    get_window().size=Vector2i(1280,800);effect=Effect.new(384)
    var world:=WorldEnvironment.new();var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.015,.022,.035);world.environment=environment
    var compositor:=Compositor.new();compositor.compositor_effects=[effect];world.compositor=compositor;add_child(world)
    camera=Camera3D.new();camera.current=true;camera.near=.0001;camera.far=20;add_child(camera)
    _build_ui();_sync_bodies();_apply();_refresh();DirAccess.make_dir_recursive_absolute("user://modular22")
func _label(parent: Node,text: String,size: int=14) -> Label:
    var item:=Label.new();item.text=text;item.add_theme_font_size_override("font_size",size);parent.add_child(item);return item
func _button(parent: Node,text: String,callback: Callable) -> Button:
    var item:=Button.new();item.text=text;item.pressed.connect(callback);parent.add_child(item);return item
func _panel(position: Vector2) -> VBoxContainer:
    var panel:=PanelContainer.new();panel.position=position;panel.custom_minimum_size=Vector2(260,0)
    var style:=StyleBoxFlat.new();style.bg_color=Color(.035,.048,.071,.98)
    for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_content_margin(side,14)
    style.corner_radius_top_left=12;style.corner_radius_top_right=12;style.corner_radius_bottom_left=12;style.corner_radius_bottom_right=12
    panel.add_theme_stylebox_override("panel",style);ui.add_child(panel)
    var box:=VBoxContainer.new();box.add_theme_constant_override("separation",8);panel.add_child(box);return box
func _slider(parent: Node,key: String,title: String,step: float=.01) -> void:
    _label(parent,title,13);var item:=HSlider.new();item.min_value=Doc.LIMITS[key][0];item.max_value=Doc.LIMITS[key][1];item.step=step;item.custom_minimum_size=Vector2(210,24)
    item.value_changed.connect(func(v: float):command({"op":"set_values","values":{key:v}}));parent.add_child(item);controls[key]=item
func _check(parent: Node,key: String,title: String) -> void:
    var item:=CheckBox.new();item.text=title;item.toggled.connect(func(v: bool):command({"op":"set_values","values":{key:v}}));parent.add_child(item);controls[key]=item
func _color(parent: Node,key: String,title: String) -> void:
    _label(parent,title,13);var item:=ColorPickerButton.new();item.custom_minimum_size=Vector2(210,30)
    item.color_changed.connect(func(c: Color):command({"op":"set_values","values":{key:[c.r,c.g,c.b]}}));parent.add_child(item);controls[key]=item
func _build_ui() -> void:
    ui=CanvasLayer.new();add_child(ui)
    var title:=Label.new();title.position=Vector2(24,18);title.text="LIE  ·  Ojos y destrucción modular";title.add_theme_font_size_override("font_size",26);ui.add_child(title)
    picture=TextureRect.new();picture.position=Vector2(298,70);picture.size=Vector2(684,684);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    picture.gui_input.connect(_picture_input);ui.add_child(picture)
    var left: VBoxContainer=_panel(Vector2(20,70));_label(left,"MAESTROS COMPARTIDOS",13).add_theme_color_override("font_color",Color(.35,.85,1))
    var tabs:=HBoxContainer.new();left.add_child(tabs)
    _button(tabs,"Ojo",func():command({"op":"set_values","values":{"mode":"eye"}}));_button(tabs,"Pared",func():command({"op":"set_values","values":{"mode":"wall"}}))
    eye_controls=VBoxContainer.new();eye_controls.add_theme_constant_override("separation",8);left.add_child(eye_controls)
    _color(eye_controls,"iris_color","Color del iris · fibras en gris")
    var presets:=HBoxContainer.new();eye_controls.add_child(presets)
    _button(presets,"Azul",func():command({"op":"set_values","values":{"iris_color":[.22,.57,.76]}}))
    _button(presets,"Verde",func():command({"op":"set_values","values":{"iris_color":[.37,.62,.28]}}))
    _button(presets,"Marrón",func():command({"op":"set_values","values":{"iris_color":[.40,.25,.13]}}))
    _slider(eye_controls,"pupil_radius","Radio de pupila · 0.8 a 3.2 mm",.00001)
    _slider(eye_controls,"gaze_yaw","Mirada horizontal")
    _slider(eye_controls,"gaze_pitch","Mirada vertical")
    _label(eye_controls,"Maestro original preparado en Blender.\nBrillo húmedo simplificado;\nrefracción de córnea pendiente.",12)
    wall_controls=VBoxContainer.new();wall_controls.add_theme_constant_override("separation",8);left.add_child(wall_controls)
    _color(wall_controls,"wall_color","Color base de ladrillo")
    _slider(wall_controls,"variation","Variación por ladrillo")
    _button(wall_controls,"Nueva variación",func():command({"op":"set_values","values":{"seed":(document.state["seed"]+1)%1000001}}))
    _check(wall_controls,"coating","Revestimiento de concreto")
    _check(wall_controls,"grouped","Agrupar módulos intactos")
    _check(wall_controls,"simulate","Simular fragmentos")
    var strike:=HBoxContainer.new();wall_controls.add_child(strike)
    cell_control=SpinBox.new();cell_control.min_value=0;cell_control.max_value=47;cell_control.value=27;cell_control.custom_minimum_size.x=70;strike.add_child(cell_control)
    _button(strike,"Golpear",func():command({"op":"strike","cell":int(cell_control.value)}))
    _button(wall_controls,"Restaurar pared",func():command({"op":"reset_wall"}))
    _label(wall_controls,"También puedes tocar un ladrillo.\n48 piezas latentes · 12 módulos\nHasta 32 fragmentos de corte.",12)
    var storage:=HBoxContainer.new();left.add_child(storage)
    _button(storage,"Guardar",func():command({"op":"save_document"}));_button(storage,"Abrir",func():command({"op":"load_document"}))
    var history:=HBoxContainer.new();left.add_child(history)
    _button(history,"Deshacer",func():command({"op":"undo"}));_button(history,"Rehacer",func():command({"op":"redo"}))
    _button(left,"Volver al taller",func():get_tree().change_scene_to_file("res://lie18_workshop.tscn"))
    var right: VBoxContainer=_panel(Vector2(1000,70));_label(right,"CÁMARA Y LUZ",13).add_theme_color_override("font_color",Color(.35,.85,1))
    _slider(right,"camera_yaw","Órbita")
    _slider(right,"camera_elevation","Altura")
    _slider(right,"distance_factor","Distancia")
    _slider(right,"light_azimuth","Dirección de luz")
    _slider(right,"light_power","Intensidad")
    _slider(right,"exposure","Exposición")
    status=_label(right,"Preparando biblioteca…",12);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.x=225
    stats=_label(right,"",12);stats.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;stats.custom_minimum_size.x=225
    var caption:=Label.new();caption.position=Vector2(310,756);caption.text="Capturas neutrales · profundidad real · fuentes invisibles · controles para agentes";caption.add_theme_font_size_override("font_size",12);ui.add_child(caption)
func _refresh() -> void:
    eye_controls.visible=document.state["mode"]=="eye";wall_controls.visible=not eye_controls.visible
    for key in controls:
        var item: Variant=controls[key]
        if item is Range:item.set_value_no_signal(float(document.state[key]))
        elif item is CheckBox:item.set_pressed_no_signal(document.state[key])
        elif item is ColorPickerButton:
            var c: Array=document.state[key];item.color=Color(c[0],c[1],c[2])
func command(request: Variant) -> Dictionary:
    var response: Dictionary=document.dispatch(request)
    if response.get("ok",false):_sync_bodies();_apply();_refresh()
    if status!=null:status.text="Cambio aplicado · revisión %d"%document.revision if response.get("ok",false) else "No aplicado: "+str(response.get("error"))
    return response
static func cell_center(cell: int) -> Vector3:return Vector3((float(cell%6)-2.5)*.252,float(cell/6)*.076+.0325,0)
func _shape(master: String) -> ConvexPolygonShape3D:
    var points:=PackedVector3Array()
    for p in effect.get("catalog")["masters"][master]["collision_vertices"]:points.append(Vector3(p[0],p[1],p[2]))
    var shape:=ConvexPolygonShape3D.new();shape.points=points;return shape
func _spawn(master: String,cell: int,serial: int) -> void:
    var body:=RigidBody3D.new();body.name="Invisible_%d_%s"%[cell,master];body.mass=.5 if master.begins_with("fragment") else 2.0;body.continuous_cd=true;body.linear_damp=.55;body.angular_damp=.7
    var collision:=CollisionShape3D.new();collision.shape=_shape(master);body.add_child(collision)
    var offset: Array=effect.get("catalog")["masters"][master]["origin_offset"]
    body.position=cell_center(cell)+Vector3(offset[0],offset[1],offset[2])
    var rng:=RandomNumberGenerator.new();rng.seed=int(document.state["seed"])+cell*37+serial*191
    body.linear_velocity=Vector3(rng.randf_range(-.35,.35),rng.randf_range(.25,.60),rng.randf_range(.35,.75));body.angular_velocity=Vector3(rng.randf_range(-4,4),rng.randf_range(-3,3),rng.randf_range(-3,3))
    body.freeze=not document.state["simulate"];add_child(body);_bodies[str(body.name)]={"body":body,"master":master,"cell":cell}
func _sync_bodies() -> void:
    if not effect.get("capture_loaded"):return
    var graph: Dictionary=Doc.connectivity(document.state)
    var desired: Dictionary={}
    for cell in graph["removed"].slice(0,MAX_FRAGMENTS/4):
        for serial in range(4):desired["Invisible_%d_fragment_%d"%[cell,serial]]={"master":"fragment_%d"%serial,"cell":cell,"serial":serial}
    for cell in graph["unsupported"]:desired["Invisible_%d_brick"%cell]={"master":"brick","cell":cell,"serial":11}
    for name in _bodies.keys():
        if not desired.has(name):
            remove_child(_bodies[name]["body"]);_bodies[name]["body"].queue_free();_bodies.erase(name)
    for name in desired:
        if not _bodies.has(name):
            var entry: Dictionary=desired[name];_spawn(entry["master"],entry["cell"],entry["serial"])
    for entry in _bodies.values():entry["body"].freeze=not document.state["simulate"] or document.state["mode"]!="wall"
    if not _statics.has(-1):
        var floor_body:=StaticBody3D.new();var floor_shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(3,.10,3);floor_shape.shape=box;floor_body.position=Vector3(0,-.05,0);floor_body.add_child(floor_shape);add_child(floor_body);_statics[-1]=floor_body
    for cell in _statics.keys():
        if cell!=-1 and not graph["supported"].has(cell):remove_child(_statics[cell]);_statics[cell].queue_free();_statics.erase(cell)
    for cell in graph["supported"]:
        if _statics.has(cell):continue
        var body:=StaticBody3D.new();var collision:=CollisionShape3D.new();collision.shape=_shape("brick");body.add_child(collision);body.position=cell_center(cell);add_child(body);_statics[cell]=body
func _add_instance(list: Array,master: String,pose: Transform3D,cell: int=-1,tile: bool=false) -> void:list.append({"master":master,"pose":pose,"cell":cell,"tile":tile})
func _instances() -> Array:
    var list: Array=[]
    if document.state["mode"]=="eye":
        _add_instance(list,"eye",Transform3D(Basis.from_euler(Vector3(deg_to_rad(document.state["gaze_pitch"]),deg_to_rad(document.state["gaze_yaw"]),0)),Vector3.ZERO));_runtime_stats={"latent_bricks":48,"grouped_modules":0,"dynamic_bodies":0,"sleeping_bodies":0};return list
    var graph: Dictionary=Doc.connectivity(document.state);var grouped: int=0
    for row in range(0,8,2):
        for col in range(0,6,2):
            var cells: Array=[row*6+col,row*6+col+1,(row+1)*6+col,(row+1)*6+col+1]
            var intact: bool=cells.all(func(cell: int):return graph["supported"].has(cell))
            if intact and document.state["grouped"]:
                _add_instance(list,"tile_coat" if document.state["coating"] else "tile_brick",Transform3D(Basis.IDENTITY,(cell_center(cells[0])+cell_center(cells[3]))*.5),cells[0],true);grouped+=1
            else:
                for cell in cells:
                    if graph["supported"].has(cell):_add_instance(list,"coated_brick" if intact and document.state["coating"] else "brick",Transform3D(Basis.IDENTITY,cell_center(cell)),cell)
    var sleeping: int=0
    for entry in _bodies.values():
        var body: RigidBody3D=entry["body"]
        if body.sleeping:sleeping+=1
        _add_instance(list,entry["master"],body.transform,entry["cell"])
    _add_instance(list,"floor",Transform3D.IDENTITY)
    _runtime_stats={"latent_bricks":48,"grouped_modules":grouped,"removed_bricks":graph["removed"].size(),"unsupported_bricks":graph["unsupported"].size(),"dynamic_bodies":_bodies.size(),"sleeping_bodies":sleeping}
    return list
func _apply() -> void:
    if camera==null or not effect.get("capture_loaded"):return
    var state: Dictionary=document.state;var eye: bool=state["mode"]=="eye"
    var target:=Vector3.ZERO if eye else Vector3(0,.28,0)
    var yaw: float=deg_to_rad(state["camera_yaw"]);var elevation: float=deg_to_rad(state["camera_elevation"])
    var distance: float=(.065 if eye else 2.10)*float(state["distance_factor"])
    camera.fov=35 if eye else 45;camera.position=target+Vector3(sin(yaw)*cos(elevation),sin(elevation),cos(yaw)*cos(elevation))*distance;camera.look_at(target)
    var list: Array=_instances();var instance_data:=PackedFloat32Array();var jobs:=PackedInt32Array();var work: int=0
    var coarse_all: bool=false
    for attempt in range(2):
        instance_data.clear();jobs.clear();work=0
        for entry in list:
            var pose: Transform3D=entry["pose"];var level: int=1 if coarse_all or str(entry["master"]).begins_with("fragment") else 0
            var master: Dictionary=effect.get("catalog")["masters"][entry["master"]];var range_data: Dictionary=master["levels"][level]
            var index: int=instance_data.size()/24
            for v in [pose.basis.x,pose.basis.y,pose.basis.z,pose.origin]:instance_data.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
            instance_data.append_array(PackedFloat32Array([entry["cell"],1 if entry["tile"] else 0,0,0,1,1,1,1]))
            jobs.append_array(PackedInt32Array([range_data["start"],range_data["count"],index,work]));work+=int(range_data["count"])
        if work<=Effect.MAX_WORK:break
        coarse_all=true
    if work>Effect.MAX_WORK or list.size()>Effect.MAX_INSTANCES:status.text="Presupuesto de reconstrucción excedido";return
    var packet:=PackedFloat32Array()
    for v in [camera.position,camera.basis.x,camera.basis.y,-camera.basis.z]:packet.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    packet.append_array(PackedFloat32Array([tan(deg_to_rad(camera.fov)*.5),1,.0001 if eye else .01,20]))
    var bytes: PackedByteArray=packet.to_byte_array();bytes.append_array(PackedInt32Array([work,list.size(),effect.get("render_size"),effect.get("render_size")]).to_byte_array())
    var angle: float=deg_to_rad(state["light_azimuth"]);var radius: float=.055 if eye else 1.5
    var light: Vector3=target+Vector3(sin(angle)*radius,.035 if eye else 1.05,cos(angle)*radius)
    var light_pose:=Transform3D(Basis.IDENTITY,light).looking_at(target,Vector3.UP)
    var values:=PackedFloat32Array([light.x,light.y,light.z,(.12 if eye else 40.0)*state["light_power"],1,.91,.83,0,.15,.18,.24,state["exposure"],1,1,.000025 if eye else .0015,.000025 if eye else .00065])
    for v in [light_pose.basis.x,light_pose.basis.y,-light_pose.basis.z]:values.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    var iris: Array=state["iris_color"];var color:=Color(iris[0],iris[1],iris[2]).srgb_to_linear();values.append_array(PackedFloat32Array([color.r,color.g,color.b,state["pupil_radius"]]))
    var wall: Array=state["wall_color"];color=Color(wall[0],wall[1],wall[2]).srgb_to_linear();values.append_array(PackedFloat32Array([color.r,color.g,color.b,state["variation"],state["seed"],0 if eye else 1,0,0]));bytes.append_array(values.to_byte_array())
    effect.call("configure",bytes,instance_data.to_byte_array(),jobs.to_byte_array(),work)
func _picture_input(event: InputEvent) -> void:
    if document.state["mode"]!="wall" or not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_LEFT or not event.pressed:return
    var uv: Vector2=event.position/picture.size;var tangent: float=tan(deg_to_rad(camera.fov)*.5)
    var ray: Vector3=-camera.basis.z+camera.basis.x*((uv.x*2-1)*tangent)+camera.basis.y*((1-uv.y*2)*tangent)
    if absf(ray.z)<.00001:return
    var t: float=(.055-camera.position.z)/ray.z
    if t<0:return
    var p: Vector3=camera.position+ray*t;var col: int=int(floor((p.x+.756)/.252));var row: int=int(floor((p.y+.0055)/.076))
    if col>=0 and col<6 and row>=0 and row<8:cell_control.value=row*6+col;command({"op":"strike","cell":row*6+col})
func agent_snapshot() -> Dictionary:
    var result: Dictionary=document.snapshot();result["capture_loaded"]=effect.get("capture_loaded");result["visible_source_meshes"]=0;result["metrics"]=_runtime_stats.duplicate()
    result["metrics"].merge({"allocation_bytes":effect.get("allocation_bytes"),"asset_uploads":effect.get("asset_uploads"),"instances":effect.get("instance_count"),"sample_invocations":effect.get("sample_invocations")})
    result["inbox"]=OS.get_user_data_dir()+"/modular22/inbox.json";result["outbox"]=OS.get_user_data_dir()+"/modular22/outbox.json";result["commands"]=["snapshot","set_values","strike","reset_wall","batch","save_document","load_document","undo","redo"]
    return result
func _poll_agent() -> void:
    var path: String="user://modular22/inbox.json"
    if not FileAccess.file_exists(path):return
    var file:=FileAccess.open(path,FileAccess.READ)
    if file==null or file.get_length()>1024*1024:return
    var request: Variant=JSON.parse_string(file.get_as_text());file.close();DirAccess.remove_absolute(path)
    var id: Variant=request.get("request_id") if request is Dictionary else null
    var response: Dictionary=command(request.get("request") if request is Dictionary and request.has("request") else request)
    var output:=FileAccess.open("user://modular22/outbox.json.tmp",FileAccess.WRITE)
    if output==null:return
    output.store_string(JSON.stringify({"request_id":id,"result":response,"snapshot":agent_snapshot()},"  ",true,true));output.close();DirAccess.rename_absolute("user://modular22/outbox.json.tmp","user://modular22/outbox.json")
func _process(delta: float) -> void:
    if effect.get("gpu_ready") and not _connected:
        texture=Texture2DRD.new();texture.texture_rd_rid=effect.get("output_rid");picture.texture=texture;_connected=true
    if document.state["mode"]=="wall" and document.state["simulate"] and _bodies.values().any(func(entry: Dictionary):return not entry["body"].sleeping):_apply()
    _poll_time+=delta
    if _poll_time>=.2:_poll_time=0;_poll_agent()
    _stats_time+=delta
    if _stats_time>=1:
        _stats_time=0
        if not effect.get("capture_loaded"):status.text=effect.get("failure")
        else:stats.text="%d maestros · una biblioteca\n%d instancias visibles\n%.1f MiB de buffers Lie\n%d cuerpos · %d dormidos\nMedición Android pendiente"%[effect.get("catalog")["masters"].size(),effect.get("instance_count"),float(effect.get("allocation_bytes"))/1048576,_runtime_stats.get("dynamic_bodies",0),_runtime_stats.get("sleeping_bodies",0)]
func _exit_tree() -> void:
    if texture!=null:texture.texture_rd_rid=RID()
    if effect!=null:effect.call("shutdown")
