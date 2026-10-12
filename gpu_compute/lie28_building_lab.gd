extends Node3D
## UI and agent edits share this validated document. Source meshes stay offline.
const Effect=preload("res://lie28_building_effect.gd")
const LIMITS={"camera_yaw":[-180,180],"camera_elevation":[-10,85],"distance_factor":[.6,2],"light_azimuth":[-180,180],"light_power":[.25,3],"exposure":[.5,4],"variation":[0,.4],"explode":[0,1]}
const MODES=["house","wall","master","fragments"]
var state: Dictionary={"mode":"house","master":"brick","camera_yaw":32.0,"camera_elevation":25.0,"distance_factor":1.0,"light_azimuth":-35.0,"light_power":1.0,"exposure":2.0,"variation":.1,"explode":0.0,"roof":true,"shadows":true}
var revision: int=0
var effect: CompositorEffect
var camera: Camera3D
var picture: TextureRect
var texture: Texture2DRD
var status: Label
var controls: Dictionary={}
var _connected: bool=false
var _time: float=0
var _metrics: Dictionary={}

func _ready() -> void:
    get_window().size=Vector2i(1280,800);effect=Effect.new(512)
    var world:=WorldEnvironment.new();var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.025,.034,.045);world.environment=environment
    var compositor:=Compositor.new();compositor.compositor_effects=[effect];world.compositor=compositor;add_child(world)
    camera=Camera3D.new();camera.current=true;camera.near=.001;camera.far=40;add_child(camera)
    _ui();_apply();_refresh()

func _label(parent: Node,text: String,size: int=14) -> Label:
    var item:=Label.new();item.text=text;item.add_theme_font_size_override("font_size",size);parent.add_child(item);return item
func _button(parent: Node,text: String,callback: Callable) -> void:
    var item:=Button.new();item.text=text;item.pressed.connect(callback);parent.add_child(item)
func _panel(ui: Node,position: Vector2) -> VBoxContainer:
    var panel:=PanelContainer.new();panel.position=position;panel.custom_minimum_size=Vector2(260,0)
    var style:=StyleBoxFlat.new();style.bg_color=Color(.04,.055,.075,.98)
    for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_content_margin(side,14)
    style.corner_radius_top_left=12;style.corner_radius_top_right=12;style.corner_radius_bottom_left=12;style.corner_radius_bottom_right=12;panel.add_theme_stylebox_override("panel",style);ui.add_child(panel)
    var box:=VBoxContainer.new();box.add_theme_constant_override("separation",8);panel.add_child(box);return box
func _slider(parent: Node,key: String,title: String) -> void:
    _label(parent,title,13);var item:=HSlider.new();item.min_value=LIMITS[key][0];item.max_value=LIMITS[key][1];item.step=.01;item.custom_minimum_size=Vector2(210,24)
    item.value_changed.connect(func(v: float):command({"op":"set_values","values":{key:v}}));parent.add_child(item);controls[key]=item
func _check(parent: Node,key: String,title: String) -> void:
    var item:=CheckBox.new();item.text=title;item.toggled.connect(func(v: bool):command({"op":"set_values","values":{key:v}}));parent.add_child(item);controls[key]=item
func _ui() -> void:
    var ui:=CanvasLayer.new();add_child(ui)
    var title:=_label(ui,"LIE  ·  Construcción modular",26);title.position=Vector2(24,18)
    picture=TextureRect.new();picture.position=Vector2(298,70);picture.size=Vector2(684,684);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;ui.add_child(picture)
    var left: VBoxContainer=_panel(ui,Vector2(20,70));_label(left,"MAESTROS DE CONSTRUCCIÓN",13).add_theme_color_override("font_color",Color(.4,.85,1))
    for pair in [["house","Casa de prueba"],["wall","Muro con aberturas"],["master","Inspeccionar maestro"],["fragments","Ladrillo y fragmentos"]]:
        var mode: String=pair[0];_button(left,pair[1],func():command({"op":"set_values","values":{"mode":mode}}))
    var select:=OptionButton.new();select.custom_minimum_size=Vector2(220,30)
    if effect.get("capture_loaded"):
        for key in effect.get("catalog")["masters"]:select.add_item(key)
    select.item_selected.connect(func(index: int):command({"op":"set_values","values":{"master":select.get_item_text(index),"mode":"master"}}));left.add_child(select);controls["master"]=select
    _slider(left,"explode","Separar / reunir los 4 fragmentos")
    _slider(left,"variation","Variación por pieza")
    _check(left,"roof","Mostrar cubierta")
    _label(left,"Módulo de muro: 1 × 0.8 m\nCasa: interior 4 × 3 m · altura 2.4 m\nPuerta: 0.75 × 1.92 m\nVentana: 0.50 × 0.48 m",12)
    _label(left,"Fuentes editables en Blender + GLB\nAlbedo y rugosidad CC0 · Poly Haven\nPrototipo de ensamblaje; sin cálculo\nestructural ni simulación de obra.",12)
    _button(left,"Volver al taller",func():get_tree().change_scene_to_file("res://lie18_workshop.tscn"))
    var right: VBoxContainer=_panel(ui,Vector2(1000,70));_label(right,"CÁMARA Y LUZ",13).add_theme_color_override("font_color",Color(.4,.85,1))
    for pair in [["camera_yaw","Órbita"],["camera_elevation","Altura"],["distance_factor","Distancia"],["light_azimuth","Dirección de luz"],["light_power","Intensidad"],["exposure","Exposición"]]:_slider(right,pair[0],pair[1])
    _check(right,"shadows","Sombras")
    status=_label(right,"Preparando biblioteca…",12);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.x=225
    var caption:=_label(ui,"Capturas RGB neutrales · maestros compartidos · profundidad real · API para agentes",12);caption.position=Vector2(310,760)

func _refresh() -> void:
    for key in controls:
        var item: Variant=controls[key]
        if item is Range:item.set_value_no_signal(float(state[key]))
        elif item is CheckBox:item.set_pressed_no_signal(state[key])
        elif item is OptionButton:
            for i in range(item.item_count):
                if item.get_item_text(i)==state[key]:item.select(i)
func command(request: Variant) -> Dictionary:
    if not request is Dictionary:return {"ok":false,"error":"request_object","revision":revision}
    if request.has("expected_revision") and request["expected_revision"]!=revision:return {"ok":false,"error":"revision_conflict","revision":revision}
    if request.get("op")=="snapshot":return {"ok":true,"snapshot":agent_snapshot(),"revision":revision}
    if request.get("op")!="set_values" or not request.get("values") is Dictionary or request["values"].is_empty():return {"ok":false,"error":"values_object","revision":revision}
    var next: Dictionary=state.duplicate(true)
    for key in request["values"]:
        if not next.has(key):return {"ok":false,"error":"unknown_field","revision":revision}
        next[key]=request["values"][key]
    if next["mode"] not in MODES:return {"ok":false,"error":"mode","revision":revision}
    if not next["master"] is String or not effect.get("catalog").get("masters",{}).has(next["master"]):return {"ok":false,"error":"master","revision":revision}
    for key in LIMITS:
        var value: Variant=next[key]
        if not (value is int or value is float) or not is_finite(float(value)) or float(value)<LIMITS[key][0] or float(value)>LIMITS[key][1]:return {"ok":false,"error":"range_"+key,"revision":revision}
        next[key]=float(value)
    for key in ["roof","shadows"]:
        if not next[key] is bool:return {"ok":false,"error":"boolean_"+key,"revision":revision}
    if next!=state:state=next;revision+=1;_apply();_refresh()
    return {"ok":true,"revision":revision}

func _add(list: Array,master: String,origin: Vector3,yaw: float=0,scale: Vector3=Vector3.ONE) -> void:
    list.append({"master":master,"pose":Transform3D(Basis(Vector3.UP,yaw).scaled_local(scale),origin)})
func _instances() -> Array:
    var list: Array=[]
    match state["mode"]:
        "master":_add(list,state["master"],Vector3.ZERO)
        "fragments":
            for i in range(4):
                var master: String="fragment_%d"%i;var offset: Array=effect.get("catalog")["masters"][master]["origin_offset"];var center:=Vector3(offset[0],offset[1],offset[2])
                var spread:=Vector3(-.075 if i%2==0 else .075,-.085 if i<2 else .085,.015 if i%2==0 else -.015)
                _add(list,master,center+spread*state["explode"])
        "wall":
            for row in range(3):
                for col in range(3):
                    var master: String="wall"
                    if col==0:master="door_head" if row==2 else "door_base"
                    elif col==2 and row==1:master="window_wall"
                    _add(list,master,Vector3(col-1,row*.8+.4,0))
            for col in range(3):_add(list,"slab",Vector3(col-1,-.05,0))
        "house":
            for row in range(3):
                for col in range(4):
                    var master: String="wall"
                    if col==1:master="door_head" if row==2 else "door_base"
                    elif col==3 and row==1:master="window_wall"
                    _add(list,master,Vector3(col-1.5,row*.8+.4,1.56));_add(list,"window_wall" if col==1 and row==1 else "wall",Vector3(col-1.5,row*.8+.4,-1.56),PI)
                for col in range(3):
                    var master: String="window_wall" if col==1 and row==1 else "wall"
                    _add(list,master,Vector3(2.06,row*.8+.4,1-col),PI/2);_add(list,master,Vector3(-2.06,row*.8+.4,col-1),-PI/2)
                for corner in [[-2.12,1.62,0],[2.12,1.62,PI/2],[2.12,-1.62,PI],[-2.12,-1.62,-PI/2]]:_add(list,"corner",Vector3(corner[0],row*.8+.4,corner[1]),corner[2])
            for x in range(4):
                for z in range(3):
                    _add(list,"slab",Vector3(x-1.5,-.05,z-1))
                    if state["roof"]:_add(list,"slab",Vector3((x-1.5)*1.06,2.45,(z-1)*1.08),0,Vector3(1.06,1,1.08))
            _add(list,"lintel",Vector3(-.5,1.96,1.56))
    return list

func _apply() -> void:
    if camera==null or not effect.get("capture_loaded"):return
    var small: bool=state["mode"] in ["master","fragments"]
    var target:=Vector3.ZERO if small else Vector3(0,1.15,0)
    var distance: float=8.6 if state["mode"]=="house" else 4.4 if state["mode"]=="wall" else .65
    if state["mode"]=="master":
        var size: Array=effect.get("catalog")["masters"][state["master"]]["bounds_size"];distance=maxf(maxf(size[0],size[1]),size[2])*2.7
        if state["master"]=="corner":target=Vector3(.125,0,-.125)
    distance*=state["distance_factor"]
    var yaw: float=deg_to_rad(state["camera_yaw"]);var elevation: float=deg_to_rad(state["camera_elevation"])
    camera.fov=42;camera.position=target+Vector3(sin(yaw)*cos(elevation),sin(elevation),cos(yaw)*cos(elevation))*distance;camera.look_at(target)
    var list: Array=_instances();var instance_data:=PackedFloat32Array();var jobs:=PackedInt32Array();var work: int=0;var level_used: int=0
    for level in range(2):
        level_used=level;instance_data.clear();jobs.clear();work=0
        for entry in list:
            var pose: Transform3D=entry["pose"];var master: Dictionary=effect.get("catalog")["masters"][entry["master"]];var range_data: Dictionary=master["levels"][level];var index: int=instance_data.size()/24
            for v in [pose.basis.x,pose.basis.y,pose.basis.z,pose.origin]:instance_data.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
            var identity: int=0 if state["mode"]=="fragments" else index*128
            instance_data.append_array(PackedFloat32Array([identity,0,0,0,1,1,1,1]));jobs.append_array(PackedInt32Array([range_data["start"],range_data["count"],index,work]));work+=int(range_data["count"])
        if work<=Effect.MAX_WORK:break
    if work>Effect.MAX_WORK or list.size()>Effect.MAX_INSTANCES:
        _metrics={"error":"work_budget","instances":list.size(),"sample_invocations":work};status.text="Presupuesto excedido";return
    var packet:=PackedFloat32Array()
    for v in [camera.position,camera.basis.x,camera.basis.y,-camera.basis.z]:packet.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    packet.append_array(PackedFloat32Array([tan(deg_to_rad(camera.fov)*.5),1,.001,40]))
    var bytes: PackedByteArray=packet.to_byte_array();bytes.append_array(PackedInt32Array([work,list.size(),effect.get("render_size"),effect.get("render_size")]).to_byte_array())
    var angle: float=deg_to_rad(state["light_azimuth"]);var radius: float=distance*.8;var light: Vector3=target+Vector3(sin(angle)*radius,radius*.9,cos(angle)*radius);var light_pose:=Transform3D(Basis.IDENTITY,light).looking_at(target,Vector3.UP)
    var spacing: float=.0008 if small else .003
    var values:=PackedFloat32Array([light.x,light.y,light.z,160*radius*radius*state["light_power"],1,.93,.85,0,.4,.45,.55,state["exposure"],1 if state["shadows"] else 0,1,spacing,spacing*.3])
    for v in [light_pose.basis.x,light_pose.basis.y,-light_pose.basis.z]:values.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    values.append_array(PackedFloat32Array([1,1,1,0,1,1,1,state["variation"],1203,1,0,0]));bytes.append_array(values.to_byte_array())
    var configured: bool=effect.call("configure",bytes,instance_data.to_byte_array(),jobs.to_byte_array(),work)
    _metrics={"instances":list.size(),"sample_invocations":work,"lod":level_used,"masters":effect.get("catalog")["masters"].size(),"visible_source_meshes":0,"configured":configured}
func agent_snapshot() -> Dictionary:
    var masters: Dictionary=effect.get("catalog").get("masters",{}) if effect!=null else {}
    return {"state":state.duplicate(true),"revision":revision,"metrics":_metrics.duplicate(),"commands":["snapshot","set_values"],"control_contract":{"modes":MODES,"booleans":["roof","shadows"],"masters":masters.keys(),"limits":LIMITS}}
func _process(delta: float) -> void:
    if effect.get("gpu_ready") and not _connected:
        texture=Texture2DRD.new();texture.texture_rd_rid=effect.get("output_rid");picture.texture=texture;_connected=true
    _time+=delta
    if _time>.5:
        _time=0
        status.text="%s\n%d maestros · %d instancias\n%d muestras · LOD %d\nBanco GPU: %d carga\nMemoria: %.1f MiB"%[state["mode"],_metrics.get("masters",0),_metrics.get("instances",0),_metrics.get("sample_invocations",0),_metrics.get("lod",0),effect.get("asset_uploads"),effect.get("allocation_bytes")/1048576.0] if effect.get("capture_loaded") else effect.get("failure")
func _exit_tree() -> void:
    if texture!=null:texture.texture_rd_rid=RID()
    if effect!=null:effect.call("shutdown")
