extends Node3D
## Complete humanoid assembled from shared captures. UI and agents share command().
const Effect=preload("res://lie_robot_effect.gd")
const Assembly=preload("res://lie_robot_assembly.gd")
const Rig=preload("res://lie26_rig.gd")
const LIMITS={"camera_yaw":[-180,180],"camera_elevation":[-15,70],"distance_factor":[.6,1.8],"light_azimuth":[-180,180],"light_power":[.2,3],"exposure":[.4,3],"variation":[0,.25],"time":[0,60],"speed":[.1,2],"grip":[0,1]}
var state: Dictionary={"mode":"manual","focus":"body","master":"plate_flat","camera_yaw":28.0,"camera_elevation":8.0,"distance_factor":1.0,"light_azimuth":-40.0,"light_power":1.0,"exposure":1.3,"variation":.08,"time":0.0,"speed":1.0,"grip":.25,
    "playing":false,"cables":true,"floor":true,"shadows":true,"foot_ik":true,"unlit":false,"coat_color":[.82,.92,1.0],
    "pose":{"right_elbow":25.0,"left_elbow":18.0,"right_abduction":10.0,"left_abduction":10.0,"head_yaw":-6.0,"root_position":[0,-.014,0]},"targets":{}}
var revision: int=0
var effect: CompositorEffect
var camera: Camera3D
var picture: TextureRect
var texture: Texture2DRD
var status: Label
var controls: Dictionary={}
var _connected: bool=false
var _time: float=0
var _animation_time: float=0
var _metrics: Dictionary={}
var _model: Dictionary={}
var _selected_joint: String="right_elbow"
var _joint_slider: HSlider

func _ready() -> void:
    get_window().size=Vector2i(1280,800);effect=Effect.new(768)
    var world:=WorldEnvironment.new();var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.025,.035,.050);world.environment=environment
    var compositor:=Compositor.new();compositor.compositor_effects=[effect];world.compositor=compositor;add_child(world)
    camera=Camera3D.new();camera.current=true;camera.near=.001;camera.far=20;add_child(camera)
    _ui();_apply();_refresh()
func _label(parent: Node,text: String,size: int=14) -> Label:
    var item:=Label.new();item.text=text;item.add_theme_font_size_override("font_size",size);parent.add_child(item);return item
func _button(parent: Node,text: String,callback: Callable) -> void:
    var item:=Button.new();item.text=text;item.pressed.connect(callback);parent.add_child(item)
func _panel(ui: Node,position: Vector2) -> VBoxContainer:
    var panel:=PanelContainer.new();panel.position=position;panel.custom_minimum_size=Vector2(260,0);var style:=StyleBoxFlat.new();style.bg_color=Color(.04,.055,.075,.98)
    for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_content_margin(side,14)
    style.corner_radius_top_left=12;style.corner_radius_top_right=12;style.corner_radius_bottom_left=12;style.corner_radius_bottom_right=12;panel.add_theme_stylebox_override("panel",style);ui.add_child(panel)
    var box:=VBoxContainer.new();box.add_theme_constant_override("separation",6);panel.add_child(box);return box
func _slider(parent: Node,key: String,title: String) -> void:
    _label(parent,title,12);var item:=HSlider.new();item.min_value=LIMITS[key][0];item.max_value=LIMITS[key][1];item.step=.01;item.custom_minimum_size=Vector2(210,20)
    item.value_changed.connect(func(v: float):command({"op":"set_values","values":{key:v}}));parent.add_child(item);controls[key]=item
func _check(parent: Node,key: String,title: String) -> void:
    var item:=CheckBox.new();item.text=title;item.toggled.connect(func(v: bool):command({"op":"set_values","values":{key:v}}));parent.add_child(item);controls[key]=item
func _storage(op: String) -> void:
    var agent: Node=get_node("/root/LieAgent")
    var result: Dictionary=await agent.call("dispatch",{"op":op,"filename":"robot.lie.json"})
    status.text="Pose guardada / restaurada" if result.get("ok",false) else str(result.get("error"))
func _ui() -> void:
    var ui:=CanvasLayer.new();add_child(ui);var title:=_label(ui,"LIE  ·  R1 / Robot de maestros",26);title.position=Vector2(24,18)
    picture=TextureRect.new();picture.position=Vector2(298,70);picture.size=Vector2(684,684);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;ui.add_child(picture)
    var left: VBoxContainer=_panel(ui,Vector2(20,70));_label(left,"ARTICULACIÓN Y MAESTROS",13).add_theme_color_override("font_color",Color(.4,.85,1))
    var views:=HBoxContainer.new();left.add_child(views)
    for pair in [["body","Robot"],["arm","Brazo"],["head","Cabeza"],["hand","Pinza"]]:
        var focus: String=pair[0];_button(views,pair[1],func():command({"op":"set_values","values":{"focus":focus}}))
    var poses:=HBoxContainer.new();left.add_child(poses)
    for pair in [["manual","Manual"],["walk","Caminar"],["reach","Alcance"]]:
        var mode: String=pair[0];_button(poses,pair[1],func():command({"op":"set_values","values":{"mode":mode}}))
    _check(left,"playing","Reproducir movimiento");_slider(left,"time","Fase de animación");_slider(left,"speed","Velocidad")
    var joint:=OptionButton.new()
    for key in Rig.LIMITS:joint.add_item(key)
    joint.item_selected.connect(func(i: int):_selected_joint=joint.get_item_text(i);_refresh());left.add_child(joint)
    for i in range(joint.item_count):
        if joint.get_item_text(i)==_selected_joint:joint.select(i)
    _joint_slider=HSlider.new();_joint_slider.custom_minimum_size=Vector2(210,20);_joint_slider.step=.1;left.add_child(_joint_slider)
    _joint_slider.value_changed.connect(func(v: float):command({"op":"set_pose","values":{_selected_joint:v}}))
    _slider(left,"grip","Cerrar la pinza")
    _check(left,"cables","Cables flexibles");_check(left,"foot_ik","Apoyo de pies / IK")
    var select:=OptionButton.new()
    if effect.get("capture_loaded"):
        for key in effect.get("catalog")["masters"]:
            if key!="ground":select.add_item(key)
    select.item_selected.connect(func(i: int):command({"op":"set_values","values":{"master":select.get_item_text(i),"focus":"master"}}));left.add_child(select);controls["master"]=select
    var save:=HBoxContainer.new();left.add_child(save);_button(save,"Guardar",func():_storage("save_state"));_button(save,"Abrir",func():_storage("load_state"))
    _label(left,"3 placas · articulaciones · pistones\nCables guiados por el mismo rig\nMapas PBR 4K · maestros compartidos",12)
    var right: VBoxContainer=_panel(ui,Vector2(1000,70));_label(right,"CÁMARA Y MATERIAL",13).add_theme_color_override("font_color",Color(.4,.85,1))
    for pair in [["camera_yaw","Órbita"],["camera_elevation","Altura"],["distance_factor","Distancia"],["light_azimuth","Luz y reflejos"],["light_power","Intensidad"],["exposure","Exposición"],["variation","Variación entre piezas"]]:_slider(right,pair[0],pair[1])
    var color:=ColorPickerButton.new();color.custom_minimum_size=Vector2(210,28);color.color_changed.connect(func(c: Color):command({"op":"set_values","values":{"coat_color":[c.r,c.g,c.b]}}));right.add_child(color);controls["coat_color"]=color
    _check(right,"shadows","Sombras");_check(right,"floor","Suelo de prueba");_check(right,"unlit","Inspeccionar albedo")
    status=_label(right,"Preparando robot…",12);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.x=225
    var caption:=_label(ui,"Capturas PBR neutrales · rig FK/IK · metal con reflejos recalculados · cables deformados en GPU",12);caption.position=Vector2(302,762)
func _refresh() -> void:
    for key in controls:
        var item: Variant=controls[key]
        if item is Range:item.set_value_no_signal(state[key])
        elif item is CheckBox:item.set_pressed_no_signal(state[key])
        elif item is OptionButton:
            for i in range(item.item_count):
                if item.get_item_text(i)==state[key]:item.select(i)
        elif item is ColorPickerButton:
            var c: Array=state[key];item.color=Color(c[0],c[1],c[2])
    if _joint_slider!=null:
        _joint_slider.min_value=Rig.LIMITS[_selected_joint][0];_joint_slider.max_value=Rig.LIMITS[_selected_joint][1];_joint_slider.set_value_no_signal(state["pose"].get(_selected_joint,0))
func validate(next: Dictionary) -> String:
    if next["mode"] not in ["manual","walk","reach"] or next["focus"] not in ["body","arm","head","hand","master"]:return "mode_or_focus"
    if not next["master"] is String or not effect.get("catalog").get("masters",{}).has(next["master"]):return "master"
    for key in LIMITS:
        var value: Variant=next[key]
        if not (value is int or value is float) or not is_finite(float(value)) or value<LIMITS[key][0] or value>LIMITS[key][1]:return "range_"+key
    for key in ["playing","cables","floor","shadows","foot_ik","unlit"]:
        if not next[key] is bool:return "boolean_"+key
    if not Rig.validate_pose(next["pose"]) or not Rig.validate_targets(next["targets"]):return "pose_or_targets"
    if not next["coat_color"] is Array or next["coat_color"].size()!=3:return "color"
    for value in next["coat_color"]:
        if not (value is int or value is float) or not is_finite(float(value)) or value<0 or value>1:return "color"
    return ""
func command(request: Variant) -> Dictionary:
    if not request is Dictionary:return {"ok":false,"error":"request_object","revision":revision}
    if request.has("expected_revision") and request["expected_revision"]!=revision:return {"ok":false,"error":"revision_conflict","revision":revision}
    if request.get("op")=="snapshot":return {"ok":true,"snapshot":agent_snapshot(),"revision":revision}
    var next: Dictionary=state.duplicate(true);var values: Variant=request.get("values")
    if not values is Dictionary or values.is_empty():return {"ok":false,"error":"values_object","revision":revision}
    if request.get("op")=="set_pose":next["pose"].merge(values,true);next["mode"]="manual"
    elif request.get("op")=="set_values":
        for key in values:
            if not next.has(key):return {"ok":false,"error":"unknown_field","revision":revision}
            next[key]=values[key]
    else:return {"ok":false,"error":"unknown_operation","revision":revision}
    var error: String=validate(next)
    if error!="":return {"ok":false,"error":error,"revision":revision}
    for key in LIMITS:next[key]=float(next[key])
    if next!=state:state=next;revision+=1;_apply();_refresh()
    return {"ok":true,"revision":revision}
func _apply() -> void:
    if camera==null or not effect.get("capture_loaded"):return
    _model=Assembly.build(effect.get("catalog"),state);var parts: Array=_model["parts"]
    var target:=Vector3(0,.95,0);var distance: float=3.35
    if state["focus"]=="arm":target=_model["rig"]["origins"][4]+Vector3(0,-.02,0);distance=1.6
    elif state["focus"]=="hand":target=_model["rig"]["origins"][5]+Basis(_model["rig"]["rotations"][5])*Vector3(0,-.13,.025);distance=.48
    elif state["focus"]=="head":target=_model["rig"]["origins"][2]+Vector3(0,.05,0);distance=.68
    elif state["focus"]=="master":
        target=Vector3.ZERO;var size: Array=effect.get("catalog")["masters"][state["master"]]["bounds_size"];distance=maxf(maxf(size[0],size[1]),size[2])*2.7
    distance*=state["distance_factor"];var yaw: float=deg_to_rad(state["camera_yaw"]);var elevation: float=deg_to_rad(state["camera_elevation"])
    camera.fov=38;camera.position=target+Vector3(sin(yaw)*cos(elevation),sin(elevation),cos(yaw)*cos(elevation))*distance;camera.look_at(target)
    var instance_data:=PackedFloat32Array();var jobs:=PackedInt32Array();var work: int=0;var used: int=0
    for level in range(2):
        used=level;instance_data.clear();jobs.clear();work=0
        for entry in parts:
            var pose: Transform3D=entry["pose"];var metadata: Dictionary=effect.get("catalog")["masters"][entry["master"]];var range_data: Dictionary=metadata["levels"][0 if entry["master"] in ["cable","ground"] else level];var index: int=instance_data.size()/24
            for v in [pose.basis.x,pose.basis.y,pose.basis.z,pose.origin]:instance_data.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
            instance_data.append_array(PackedFloat32Array([index*128,entry["curve"],entry["radius_scale"],0,1,1,1,entry["emission"]]));jobs.append_array(PackedInt32Array([range_data["start"],range_data["count"],index,work]));work+=int(range_data["count"])
        if work<=Effect.MAX_WORK:break
    if work>Effect.MAX_WORK or parts.size()>Effect.MAX_INSTANCES:_metrics={"error":"work_budget","instances":parts.size(),"sample_invocations":work};return
    var packet:=PackedFloat32Array()
    for v in [camera.position,camera.basis.x,camera.basis.y,-camera.basis.z]:packet.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    packet.append_array(PackedFloat32Array([tan(deg_to_rad(camera.fov)*.5),1,.001,20]));var bytes: PackedByteArray=packet.to_byte_array();bytes.append_array(PackedInt32Array([work,parts.size(),effect.get("render_size"),effect.get("render_size")]).to_byte_array())
    var angle: float=deg_to_rad(state["light_azimuth"]);var radius: float=distance*.70;var light: Vector3=target+Vector3(sin(angle)*radius,radius*.85,cos(angle)*radius);var light_pose:=Transform3D(Basis.IDENTITY,light).looking_at(target,Vector3.UP)
    var values:=PackedFloat32Array([light.x,light.y,light.z,80*radius*radius*state["light_power"],1,.94,.86,0,.5,.6,.75,state["exposure"],1 if state["shadows"] else 0,1,.001,.0008])
    for v in [light_pose.basis.x,light_pose.basis.y,-light_pose.basis.z]:values.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    var c: Array=state["coat_color"];var color:=Color(c[0],c[1],c[2]).srgb_to_linear();values.append_array(PackedFloat32Array([color.r,color.g,color.b,0,1,1,1,state["variation"],1203,1,angle,1 if not state["unlit"] else -1]));bytes.append_array(values.to_byte_array())
    var configured: bool=effect.call("configure_robot",bytes,instance_data.to_byte_array(),jobs.to_byte_array(),work,_model["curves"].to_byte_array())
    _metrics={"instances":parts.size(),"sample_invocations":work,"lod":used,"masters":effect.get("catalog")["masters"].size(),"visible_source_meshes":0,"cables":parts.filter(func(p: Dictionary):return p["curve"]>=0).size(),"configured":configured,"ik":_model["rig"]["ik"]}
func agent_snapshot() -> Dictionary:
    var masters: Dictionary=effect.get("catalog").get("masters",{}) if effect!=null else {};var parts: Array=[]
    for p in _model.get("parts",[]):
        var pose: Transform3D=p["pose"];parts.append({"master":p["master"],"bone":p["bone"],"curve":p["curve"],"radius_scale":p["radius_scale"],"basis":[Rig.array(pose.basis.x),Rig.array(pose.basis.y),Rig.array(pose.basis.z)],"origin":Rig.array(pose.origin)})
    var paths: Array=[]
    for p in _model.get("paths",[]):paths.append({"length":p["length"],"requested_length":p["requested_length"],"clamped":p["clamped"],"endpoints":p["endpoints"]})
    return {"state":state.duplicate(true),"revision":revision,"metrics":_metrics.duplicate(true),"assembly":parts,"curve_frames":Array(_model.get("curves",PackedFloat32Array())),"cable_paths":paths,"commands":["snapshot","set_values","set_pose"],"control_contract":{"modes":["manual","walk","reach"],"focus":["body","arm","head","hand","master"],"booleans":["playing","cables","floor","shadows","foot_ik","unlit"],"masters":masters.keys(),"limits":LIMITS,"pose_limits":Rig.LIMITS}}
func _process(delta: float) -> void:
    if effect.get("gpu_ready") and not _connected:texture=Texture2DRD.new();texture.texture_rd_rid=effect.get("output_rid");picture.texture=texture;_connected=true
    if state["playing"]:
        state["time"]=fmod(state["time"]+delta*state["speed"],60.0);_animation_time+=delta
        if _animation_time>=1.0/30:_animation_time=0;revision+=1;_apply()
    _time+=delta
    if _time>.5:
        _time=0
        status.text="%s · %s\n%d maestros · %d piezas\n%d muestras · LOD %d\n%d cables · banco GPU: %d carga\nMemoria: %.1f MiB"%[state["mode"],state["focus"],_metrics.get("masters",0),_metrics.get("instances",0),_metrics.get("sample_invocations",0),_metrics.get("lod",0),_metrics.get("cables",0),effect.get("asset_uploads"),effect.get("allocation_bytes")/1048576.0] if effect.get("capture_loaded") else effect.get("failure")
func _exit_tree() -> void:
    if texture!=null:texture.texture_rd_rid=RID()
    if effect!=null:effect.call("shutdown")
