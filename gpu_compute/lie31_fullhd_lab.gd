extends Node3D
## UI and agent edits share this validated document. Source meshes stay offline.
const Effect=preload("res://lie31_fullhd_effect.gd")
const LIMITS={"camera_yaw":[-180,180],"camera_elevation":[-10,85],"distance_factor":[.6,2],"light_azimuth":[-180,180],"light_power":[.25,3],"exposure":[.5,4],"variation":[0,.4],"explode":[0,1],"seed":[0,999999],"roughness_variation":[0,.2]}
const MODES=["wall","master"]
var state: Dictionary={"mode":"wall","master":"brick","camera_yaw":12.0,"camera_elevation":7.0,"distance_factor":1.0,"light_azimuth":-35.0,"light_power":1.0,"exposure":2.0,"variation":.12,"roughness_variation":.06,"seed":29,"explode":0.0,"roof":true,"shadows":true}
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
    get_window().size=Vector2i(1280,800);effect=Effect.new(1080)
    var world:=WorldEnvironment.new();var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.025,.034,.045);world.environment=environment
    var compositor:=Compositor.new();compositor.compositor_effects=[effect];world.compositor=compositor;add_child(world)
    camera=Camera3D.new();camera.current=true;camera.near=.001;camera.far=40;add_child(camera)
    _ui();_apply();_refresh();_build_invisible_proxies()

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
    var title:=_label(ui,"LIE 31 · Captura 1080 × 1080 nativa",26);title.position=Vector2(24,18)
    picture=TextureRect.new();picture.position=Vector2(298,70);picture.size=Vector2(684,684);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;ui.add_child(picture)
    var left: VBoxContainer=_panel(ui,Vector2(20,70));_label(left,"MAESTROS DE CONSTRUCCIÓN",13).add_theme_color_override("font_color",Color(.4,.85,1))
    for pair in [["wall","Pared de ladrillos"],["master","Inspeccionar maestro"]]:
        var mode: String=pair[0];_button(left,pair[1],func():command({"op":"set_values","values":{"mode":mode}}))
    var select:=OptionButton.new();select.custom_minimum_size=Vector2(220,30)
    if effect.get("capture_loaded"):
        for key in effect.get("catalog")["masters"]:select.add_item(key)
    select.item_selected.connect(func(index: int):command({"op":"set_values","values":{"master":select.get_item_text(index),"mode":"master"}}));left.add_child(select);controls["master"]=select
    _slider(left,"seed","Semilla reproducible")
    _slider(left,"variation","Variación de tono")
    _slider(left,"roughness_variation","Variación rugosidad")
    _label(left,"126 ladrillos HD · 1 fondo de mortero\n3 maestros compartidos · 127 instancias\nAparejo corrido y extremos cerrados\nRelieve iluminado · tintes estables",12)
    _label(left,"Nueva fuente fotográfica 4K CC0\nAltura, normales y rugosidad reales\n3 maestros GPU compartidos\nRelieve generado; NO escaneo 3D original.",12)
    _button(left,"Volver al taller",func():get_tree().change_scene_to_file("res://lie18_workshop.tscn"))
    var right: VBoxContainer=_panel(ui,Vector2(1000,70));_label(right,"CÁMARA Y LUZ",13).add_theme_color_override("font_color",Color(.4,.85,1))
    for pair in [["camera_yaw","Órbita"],["camera_elevation","Altura"],["distance_factor","Distancia"],["light_azimuth","Dirección de luz"],["light_power","Intensidad"],["exposure","Exposición"]]:_slider(right,pair[0],pair[1])
    _check(right,"shadows","Sombras")
    status=_label(right,"Preparando biblioteca…",12);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.x=225
    var caption:=_label(ui,"LIE31 · 1080² pixels reales · Vulkan software",12);caption.position=Vector2(310,760)

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
func _hash32(x: int) -> int:
    x &= 0xffffffff
    x ^= x >> 16
    x = (x * 0x7feb352d) & 0xffffffff
    x ^= x >> 15
    x = (x * 0x846ca68b) & 0xffffffff
    return (x ^ (x >> 16)) & 0xffffffff

func _random(row: int,col: int,channel: int) -> float:
    var seed: int=int(state["seed"])
    return float(_hash32(seed*0x9e3779b1 ^ row*0x85ebca77 ^ col*0xc2b2ae3d ^ channel*0x27d4eb2f))/4294967295.0

func _brick_tint(row: int,col: int) -> Array:
    var variation: float=state["variation"]*(2.0*_random(row,col,0)-1.0)
    var roughness: float=state["roughness_variation"]*(2.0*_random(row,col,1)-1.0)
    var palette: int=mini(int(_random(row,col,2)*3.0),2)
    var tone: float=1.0+variation
    # The existing CC0 Factory Brick source has a muted tan clay pigment.
    # Red/oxidized linear-albedo tints keep every sampled shadow and pore,
    # not a flat uniform RGB replacement.
    if palette==0:return [1.08*tone,1.00*tone,.98*tone,roughness]
    if palette==1:return [.99*tone,.95*tone,.94*tone,roughness]
    return [1.14*tone,1.04*tone,1.01*tone,roughness]

func _brick(list: Array,name: String,x: float,y: float,row: int,col: int) -> void:
    var center:=Vector3(x,y,0.0)
    list.append({"master":name,"pose":Transform3D(Basis.IDENTITY,center),
        "tint":_brick_tint(row,col),"row":row,"column":col})

func _instances() -> Array:
    var list: Array=[]
    if state["mode"]=="master":
        list.append({"master":state["master"],"pose":Transform3D.IDENTITY,
            "tint":[1.0,1.0,1.0,0.0]})
        return list
    # Mortar 7 mm recessed behind the +Z brick surface; unlike LIE29,
    # gaps do not show the transparent black compositor background.
    var mortar_basis:=Basis.IDENTITY.scaled_local(Vector3(2.5,1.2,.05))
    list.append({"master":"concrete_panel",
        "pose":Transform3D(mortar_basis,Vector3(0.0,.48,.05)),
        "tint":[.58,.51,.44,0.03],"row":-1,"column":-1})
    # Six rows: 10 full bricks. Alternate rows: 9 full + 2 half bricks.
    # Every course ends at exactly x=+-1.245 m, allowing .01m vertical joints.
    # All 126 bricks have individual deterministic tint and logical proxy.
    for row in range(12):
        var y: float=(float(row)+.5)*.08
        if row%2==0:
            for col in range(10):
                _brick(list,"brick",(float(col)-4.5)*.25,y,row,col)
        else:
            _brick(list,"half_brick",-1.1875,y,row,0)
            for col in range(9):
                _brick(list,"brick",(float(col)-4.0)*.25,y,row,col+1)
            _brick(list,"half_brick",1.1875,y,row,10)
    return list

func _build_invisible_proxies() -> void:
    var parent:=Node3D.new()
    parent.name="InvisibleBricks"
    add_child(parent)
    var full:=BoxShape3D.new()
    full.size=Vector3(.24,.07,.12)
    var half:=BoxShape3D.new()
    half.size=Vector3(.115,.07,.12)
    for entry in _instances():
        if entry["master"]=="concrete_panel":continue
        var body:=StaticBody3D.new()
        body.name="Brick_%02d_%02d"%[entry["row"],entry["column"]]
        body.transform=entry["pose"]
        var shape:=CollisionShape3D.new()
        shape.shape=half if entry["master"]=="half_brick" else full
        body.add_child(shape)
        parent.add_child(body)

func _apply() -> void:
    if camera==null or not effect.get("capture_loaded"):return
    var small: bool=state["mode"]=="master"
    var target:=Vector3.ZERO if small else Vector3(0,.48,0)
    var distance: float=.65 if small else 3.65
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
            var identity: int=index*128
            var tint: Array=entry.get("tint",[1.0,1.0,1.0,0.0])
            instance_data.append_array(PackedFloat32Array([identity,0,0,0,float(tint[0]),float(tint[1]),float(tint[2]),float(tint[3])]));jobs.append_array(PackedInt32Array([range_data["start"],range_data["count"],index,work]));work+=int(range_data["count"])
        if work<=Effect.MAX_WORK:break
    if work>Effect.MAX_WORK or list.size()>Effect.MAX_INSTANCES:
        _metrics={"error":"work_budget","instances":list.size(),"sample_invocations":work};status.text="Presupuesto excedido";return
    var packet:=PackedFloat32Array()
    for v in [camera.position,camera.basis.x,camera.basis.y,-camera.basis.z]:packet.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    packet.append_array(PackedFloat32Array([tan(deg_to_rad(camera.fov)*.5),1,.001,40]))
    var bytes: PackedByteArray=packet.to_byte_array();bytes.append_array(PackedInt32Array([work,list.size(),effect.get("render_size"),effect.get("render_size")]).to_byte_array())
    var angle: float=deg_to_rad(state["light_azimuth"]);var radius: float=distance*.8;var light: Vector3=target+Vector3(sin(angle)*radius,radius*.9,cos(angle)*radius);var light_pose:=Transform3D(Basis.IDENTITY,light).looking_at(target,Vector3.UP)
    var spacing: float=.0008 if small else .0015
    var values:=PackedFloat32Array([light.x,light.y,light.z,160*radius*radius*state["light_power"],1,.93,.85,0,.4,.45,.55,state["exposure"],1 if state["shadows"] else 0,1,spacing,spacing*.3])
    for v in [light_pose.basis.x,light_pose.basis.y,-light_pose.basis.z]:values.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    values.append_array(PackedFloat32Array([1,1,1,0,1,1,1,0,1203,1,0,0]));bytes.append_array(values.to_byte_array())
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
