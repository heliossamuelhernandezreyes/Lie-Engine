extends Node3D
## Playable collision world. Widgets, keyboard and agents share command().
const Effect=preload("res://lie_robot_world_effect.gd")
const Assembly=preload("res://lie_robot_assembly.gd")
const Layout=preload("res://lie_robot_world_layout.gd")
const Controller=preload("res://lie_robot_controller.gd")
const Rig=preload("res://lie26_rig.gd")
const LIMITS={"turn":[-1,1],"walk_speed":[.2,1.5],"camera_yaw":[-180,180],"camera_elevation":[5,65],"camera_distance":[1.5,7],"light_azimuth":[-180,180],"light_power":[.2,3],"exposure":[.4,3],"grip":[0,1]}
const BOOLEANS=["playing","roof","shadows","cables","unlit"]
var state: Dictionary={"move":[0.0,0.0],"turn":0.0,"walk_speed":.85,"playing":false,"view":"third_person","camera_yaw":-15.0,"camera_elevation":22.0,"camera_distance":3.2,"light_azimuth":-40.0,"light_power":1.0,"exposure":1.7,"grip":.25,"roof":false,"shadows":true,"cables":true,"unlit":false,"motion":Controller.initial_motion()}
var revision: int=0
var effect: CompositorEffect
var camera: Camera3D
var actor: CharacterBody3D
var picture: TextureRect
var texture: Texture2DRD
var controls: Dictionary={}
var status: Label
var _collision_root: Node3D
var _environment: Array=[]
var _model: Dictionary={}
var _metrics: Dictionary={}
var _queued_ticks: int=0
var _render_dirty: bool=false
var _connected: bool=false
var _keyboard: Dictionary={}
var _dragging: bool=false
var _ui_time: float=0
func _ready() -> void:
    get_window().size=Vector2i(1280,800);effect=Effect.new(768)
    var world:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.025,.035,.05);world.environment=env
    var compositor:=Compositor.new();compositor.compositor_effects=[effect];world.compositor=compositor;add_child(world)
    camera=Camera3D.new();camera.current=true;camera.near=.02;camera.far=40;camera.fov=44;add_child(camera)
    actor=Controller.new();actor.name="R2CollisionActor";add_child(actor);actor.restore(state["motion"])
    _ui();_rebuild_environment();_apply();_refresh()
func _label(parent: Node,text: String,size: int=14) -> Label:
    var item:=Label.new();item.text=text;item.add_theme_font_size_override("font_size",size);parent.add_child(item);return item
func _button(parent: Node,text: String,callback: Callable) -> Button:
    var item:=Button.new();item.text=text;item.pressed.connect(callback);parent.add_child(item);return item
func _panel(ui: Node,position: Vector2) -> VBoxContainer:
    var panel:=PanelContainer.new();panel.position=position;panel.custom_minimum_size=Vector2(252,0);var style:=StyleBoxFlat.new();style.bg_color=Color(.04,.055,.075,.98)
    for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_content_margin(side,14)
    for property in ["corner_radius_top_left","corner_radius_top_right","corner_radius_bottom_left","corner_radius_bottom_right"]:style.set(property,12)
    panel.add_theme_stylebox_override("panel",style);ui.add_child(panel);var box:=VBoxContainer.new();box.add_theme_constant_override("separation",8);panel.add_child(box);return box
func _slider(parent: Node,key: String,label: String) -> void:
    _label(parent,label,12);var item:=HSlider.new();item.min_value=LIMITS[key][0];item.max_value=LIMITS[key][1];item.step=.01;item.custom_minimum_size=Vector2(212,20)
    item.value_changed.connect(func(v: float):command({"op":"set_values","values":{key:v}}));parent.add_child(item);controls[key]=item
func _check(parent: Node,key: String,label: String) -> void:
    var item:=CheckBox.new();item.text=label;item.toggled.connect(func(v: bool):command({"op":"set_values","values":{key:v}}));parent.add_child(item);controls[key]=item
func _storage(op: String) -> void:
    var result: Dictionary=await get_node("/root/LieAgent").call("dispatch",{"op":op,"filename":"robot-world.lie.json"})
    status.text="Estado guardado / restaurado" if result.get("ok",false) else str(result.get("error"))
func _hold(parent: Node,label: String,move: Array,turn: float=0) -> void:
    var button:=Button.new();button.text=label;button.custom_minimum_size=Vector2(102,44);parent.add_child(button)
    button.button_down.connect(func():command({"op":"set_values","values":{"move":move,"turn":turn,"playing":true}}))
    button.button_up.connect(func():command({"op":"set_values","values":{"move":[0,0],"turn":0}}))
func _ui() -> void:
    var ui:=CanvasLayer.new();add_child(ui);_label(ui,"LIE  ·  R2 / Robot y casa",26).position=Vector2(24,18)
    picture=TextureRect.new();picture.position=Vector2(290,70);picture.size=Vector2(700,700);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.mouse_filter=Control.MOUSE_FILTER_PASS;picture.gui_input.connect(_picture_input);ui.add_child(picture)
    var left: VBoxContainer=_panel(ui,Vector2(20,70));_label(left,"RECORRER LA CASA",14).add_theme_color_override("font_color",Color(.4,.85,1))
    _label(left,"WASD / flechas: moverse\nQ / E: girar · espacio: pausa\nArrastra la imagen: cámara",12)
    for row in [[["Avanzar",[0,1],0],["Retroceder",[0,-1],0]],[["Izquierda",[-1,0],0],["Derecha",[1,0],0]],[["Girar ←",[0,0],1],["Girar →",[0,0],-1]]]:
        var line:=HBoxContainer.new();left.add_child(line)
        for p in row:_hold(line,p[0],p[1],p[2])
    _check(left,"playing","Simulación activa");_slider(left,"walk_speed","Velocidad de desplazamiento");_slider(left,"grip","Cerrar pinzas")
    _button(left,"Volver a la entrada",func():command({"op":"reset"}))
    _button(left,"Dar 1 segundo de pasos",func():command({"op":"advance","ticks":60}))
    var storage:=HBoxContainer.new();left.add_child(storage);_button(storage,"Guardar",func():_storage("save_state"));_button(storage,"Abrir",func():_storage("load_state"))
    _label(left,"Pasos ligados a distancia real\nPuerta libre: 0.90 × 2.30 m\nCapsula con colisiones y gravedad\nR1 y casa comparten profundidad",12)
    var right: VBoxContainer=_panel(ui,Vector2(1008,70));_label(right,"CÁMARA Y ENTORNO",14).add_theme_color_override("font_color",Color(.4,.85,1))
    var views:=HBoxContainer.new();right.add_child(views)
    for p in [["third_person","Seguir"],["overview","Ver casa"]]:
        var mode: String=p[0];_button(views,p[1],func():command({"op":"set_values","values":{"view":mode}}))
    for p in [["camera_yaw","Órbita"],["camera_elevation","Altura"],["camera_distance","Distancia"],["light_azimuth","Dirección de luz"],["light_power","Intensidad"],["exposure","Exposición"]]:_slider(right,p[0],p[1])
    _check(right,"roof","Mostrar cubierta");_check(right,"shadows","Sombras");_check(right,"cables","Cables");_check(right,"unlit","Inspeccionar albedo")
    status=_label(right,"Preparando recorrido…",12);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.x=220
func _picture_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:_dragging=event.pressed
    if event is InputEventMouseMotion and _dragging:
        command({"op":"set_values","values":{"camera_yaw":clampf(state["camera_yaw"]-event.relative.x*.3,-180,180),"camera_elevation":clampf(state["camera_elevation"]+event.relative.y*.2,5,65)}})
func _input(event: InputEvent) -> void:
    if not event is InputEventKey or event.echo:return
    if event.physical_keycode==KEY_SPACE:
        get_viewport().set_input_as_handled()
        if event.pressed:command({"op":"set_values","values":{"playing":not state["playing"]}})
        return
    var key: int=event.physical_keycode
    if key not in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_Q,KEY_E,KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT]:return
    get_viewport().set_input_as_handled()
    _keyboard[key]=event.pressed
    var x: float=float(_keyboard.get(KEY_D,false) or _keyboard.get(KEY_RIGHT,false))-float(_keyboard.get(KEY_A,false) or _keyboard.get(KEY_LEFT,false))
    var y: float=float(_keyboard.get(KEY_W,false) or _keyboard.get(KEY_UP,false))-float(_keyboard.get(KEY_S,false) or _keyboard.get(KEY_DOWN,false))
    var turn: float=float(_keyboard.get(KEY_Q,false))-float(_keyboard.get(KEY_E,false))
    command({"op":"set_values","values":{"move":[x,y],"turn":turn,"playing":true}})
func _refresh() -> void:
    for key in controls:
        var item: Variant=controls[key]
        if item is Range:item.set_value_no_signal(state[key])
        elif item is CheckBox:item.set_pressed_no_signal(state[key])
func validate(next: Dictionary) -> String:
    if next["view"] not in ["third_person","overview"]:return "view"
    for key in BOOLEANS:
        if not next[key] is bool:return "boolean_"+key
    for key in LIMITS:
        var value: Variant=next[key]
        if not (value is int or value is float) or not is_finite(float(value)) or value<LIMITS[key][0] or value>LIMITS[key][1]:return "range_"+key
    if not next["move"] is Array or next["move"].size()!=2:return "move"
    for v in next["move"]:
        if not (v is int or v is float) or not is_finite(float(v)) or absf(v)>1:return "move"
    var m: Variant=next["motion"]
    if not m is Dictionary or m.keys().size()!=Controller.initial_motion().keys().size():return "motion"
    for key in Controller.initial_motion():
        if not m.has(key):return "motion"
    if not Rig.valid_vector(m["position"],5.5) or not Rig.valid_vector(m["velocity"],12):return "motion_vector"
    if m["position"][1]<-.05 or m["position"][1]>.15:return "motion_height"
    for p in [["heading",-180,180],["phase",0,1],["travel",0,100000],["speed",0,3],["blend",0,1]]:
        var v: Variant=m[p[0]]
        if not (v is int or v is float) or not is_finite(float(v)) or v<p[1] or v>p[2]:return "motion_"+p[0]
    var ticks: Variant=m["ticks"]
    if not (ticks is int or ticks is float) or not is_finite(float(ticks)) or ticks!=floor(float(ticks)) or ticks<0 or not m["grounded"] is bool or not m["walking"] is bool:return "motion_flags"
    if not m["feet"] is Dictionary or m["feet"].keys().size()!=2:return "feet"
    for side in ["right","left"]:
        var f: Variant=m["feet"].get(side)
        if not f is Dictionary or f.keys().size()!=6 or not f.get("swing") is bool:return "feet"
        var phase: Variant=f.get("phase")
        if not (phase is int or phase is float) or not is_finite(float(phase)) or phase<0 or phase>1:return "feet_phase"
        for key in ["plant","start","end","target"]:
            if not Rig.valid_vector(f.get(key),7):return "feet_vector"
        if Rig.vector(f["target"]).distance_to(Rig.vector(m["position"])+Vector3(0,.105,0))>.65:return "feet_reach"
    return ""
func command(request: Variant) -> Dictionary:
    if not request is Dictionary:return {"ok":false,"error":"request_object","revision":revision}
    if request.has("expected_revision") and request["expected_revision"]!=revision:return {"ok":false,"error":"revision_conflict","revision":revision}
    var op: String=str(request.get("op",""))
    if op=="snapshot":return {"ok":true,"snapshot":agent_snapshot(),"revision":revision}
    if op=="advance":
        var ticks: Variant=request.get("ticks")
        if not (ticks is int or ticks is float) or not is_finite(float(ticks)) or ticks!=floor(float(ticks)) or ticks<1 or ticks>600:return {"ok":false,"error":"ticks","revision":revision}
        if state["playing"] or _queued_ticks>0:return {"ok":false,"error":"simulation_busy","revision":revision}
        _queued_ticks=int(ticks);return {"ok":true,"revision":revision,"target_tick":state["motion"]["ticks"]+int(ticks)}
    if _queued_ticks>0:return {"ok":false,"error":"simulation_busy","revision":revision}
    var next: Dictionary=state.duplicate(true)
    if op=="reset":next["motion"]=Controller.initial_motion();next["move"]=[0,0];next["turn"]=0;next["playing"]=false
    elif op=="set_values":
        var values: Variant=request.get("values")
        if not values is Dictionary or values.is_empty():return {"ok":false,"error":"values_object","revision":revision}
        for key in values:
            if not next.has(key):return {"ok":false,"error":"unknown_field","revision":revision}
            next[key]=values[key]
    else:return {"ok":false,"error":"unknown_operation","revision":revision}
    var error: String=validate(next)
    if not error.is_empty():return {"ok":false,"error":error,"revision":revision}
    next["motion"]["ticks"]=int(next["motion"]["ticks"])
    if next["motion"]["position"]!=state["motion"]["position"] and actor.overlaps_world(Rig.vector(next["motion"]["position"])):return {"ok":false,"error":"motion_collision","revision":revision}
    if next!=state:
        var restore: bool=next["motion"]!=state["motion"];var rebuild: bool=next["roof"]!=state["roof"];state=next;revision+=1
        if restore:actor.restore(state["motion"])
        if rebuild:_rebuild_environment()
        _apply();_refresh()
    return {"ok":true,"revision":revision}
func _rebuild_environment() -> void:
    if not effect.get("capture_loaded"):return
    if _collision_root!=null:remove_child(_collision_root);_collision_root.queue_free()
    _environment=Layout.instances(state["roof"]);_collision_root=Layout.collisions(self,_environment,effect.get("catalog"))
func _build_model() -> void:
    _model=Assembly.build(effect.get("catalog"),actor.rig_state(state["motion"],state["grip"],state["cables"]))
    var frame:=Transform3D(Basis(Vector3.UP,deg_to_rad(state["motion"]["heading"])),Rig.vector(state["motion"]["position"]))
    for p in _model["parts"]:p["pose"]=frame*p["pose"]
    var curves: PackedFloat32Array=_model["curves"]
    for i in range(0,curves.size(),12):
        for offset in [0,4,8]:
            var v:=Vector3(curves[i+offset],curves[i+offset+1],curves[i+offset+2]);v=frame*v if offset==0 else frame.basis*v
            curves[i+offset]=v.x;curves[i+offset+1]=v.y;curves[i+offset+2]=v.z
    _model["curves"]=curves
func _apply() -> void:
    if camera==null or not effect.get("capture_loaded"):return
    _build_model()
    if state["view"]=="third_person":camera.transform=actor.camera_pose(state["motion"],state["camera_yaw"],state["camera_elevation"],state["camera_distance"])
    else:
        var a: float=deg_to_rad(35+state["camera_yaw"]);var e: float=deg_to_rad(maxf(state["camera_elevation"],35));var target:=Vector3(-.25,1.0,.65)
        camera.transform=Transform3D(Basis.IDENTITY,target+Vector3(sin(a)*cos(e),sin(e),cos(a)*cos(e))*11.2).looking_at(target)
    var parts: Array=_model["parts"].duplicate();parts.append_array(_environment);var instances:=PackedFloat32Array();var jobs:=PackedInt32Array();var work: int=0;var lod: int=0
    for level in range(2):
        work=0;instances.clear();jobs.clear();lod=level
        for p in parts:
            var pose: Transform3D=p["pose"];var metadata: Dictionary=effect.get("catalog")["masters"][p["master"]];var span: Dictionary=metadata["levels"][0 if p["master"] in ["ground","cable"] else level];var index: int=instances.size()/24
            for v in [pose.basis.x,pose.basis.y,pose.basis.z,pose.origin]:instances.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
            instances.append_array(PackedFloat32Array([index*128,p["curve"],p["radius_scale"],0,1,1,1,p["emission"]]));jobs.append_array(PackedInt32Array([span["start"],span["count"],index,work]));work+=span["count"]
        if work<=effect.maximum_work():break
    if work>effect.maximum_work() or parts.size()>effect.maximum_instances():_metrics={"error":"work_budget","instances":parts.size(),"sample_invocations":work};return
    var packet:=PackedFloat32Array()
    for v in [camera.position,camera.basis.x,camera.basis.y,-camera.basis.z]:packet.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    packet.append_array(PackedFloat32Array([tan(deg_to_rad(camera.fov)*.5),1,.02,40]));var bytes: PackedByteArray=packet.to_byte_array();bytes.append_array(PackedInt32Array([work,parts.size(),effect.get("render_size"),effect.get("render_size")]).to_byte_array())
    var a: float=deg_to_rad(state["light_azimuth"]);var light:=Vector3(sin(a)*6.4,7.0,cos(a)*6.4);var light_pose:=Transform3D(Basis.IDENTITY,light).looking_at(Vector3(0,1,0))
    var values:=PackedFloat32Array([light.x,light.y,light.z,3276*state["light_power"],1,.94,.86,0,.5,.6,.75,state["exposure"],1 if state["shadows"] else 0,1,.003,.001])
    for v in [light_pose.basis.x,light_pose.basis.y,-light_pose.basis.z]:values.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    values.append_array(PackedFloat32Array([.638,.828,1,0,1,1,1,.10,1203,1,a,1 if not state["unlit"] else -1]));bytes.append_array(values.to_byte_array())
    var configured: bool=effect.configure_robot(bytes,instances.to_byte_array(),jobs.to_byte_array(),work,_model["curves"].to_byte_array())
    _metrics={"configured":configured,"instances":parts.size(),"robot_instances":_model["parts"].size(),"environment_instances":_environment.size(),"sample_invocations":work,"lod":lod,"visible_source_meshes":0,"ik":_model["rig"]["ik"],"camera_fraction":actor.last_camera_fraction,"colliders":_collision_root.get_child_count() if _collision_root!=null else 0}
func _physics_process(delta: float) -> void:
    if actor==null:return
    if state["playing"] or _queued_ticks>0:
        actor.step(state["motion"],Vector2(state["move"][0],state["move"][1]),state["turn"],state["walk_speed"],delta)
        if _queued_ticks>0:_queued_ticks-=1
        revision+=1;_render_dirty=true
func _process(delta: float) -> void:
    if effect.get("gpu_ready") and not _connected:texture=Texture2DRD.new();texture.texture_rd_rid=effect.get("output_rid");picture.texture=texture;_connected=true
    if _render_dirty:_render_dirty=false;_apply()
    _ui_time+=delta
    if _ui_time>.3:
        _ui_time=0;var m: Dictionary=state["motion"]
        status.text="%.2f m/s · recorrido %.2f m\n%s · %d pasos de física\n%d piezas · LOD %d\n%d muestras · %d colisiones\nCámara libre: %.0f%%\nBanco GPU: %d carga · %.1f MiB"%[m["speed"],m["travel"],"Apoyo en suelo" if m["grounded"] else "En reposo / sin apoyo",m["ticks"],_metrics.get("instances",0),_metrics.get("lod",0),_metrics.get("sample_invocations",0),_metrics.get("colliders",0),actor.last_camera_fraction*100,effect.get("asset_uploads"),effect.get("allocation_bytes")/1048576.0] if effect.get("capture_loaded") else effect.get("failure")
func agent_snapshot() -> Dictionary:
    return {"state":state.duplicate(true),"revision":revision,"metrics":_metrics.duplicate(true),"assembly":serialize_parts(_model.get("parts",[])),"environment":serialize_parts(_environment),"curve_frames":Array(_model.get("curves",PackedFloat32Array())),"motion":{"remaining_ticks":_queued_ticks,"contacts":actor.last_contacts.duplicate(true) if actor!=null else []},"camera":{"position":Rig.array(camera.position) if camera!=null else [],"fraction":actor.last_camera_fraction if actor!=null else 1},"commands":["snapshot","set_values","reset","advance"],"control_contract":{"fields":state.keys(),"limits":LIMITS,"booleans":BOOLEANS,"views":["third_person","overview"],"move":{"shape":[2],"range":[-1,1],"space":"character-local x/right, y/forward; diagonal normalized"},"advance":{"ticks":[1,600],"asynchronous":true,"completion":"motion.remaining_ticks == 0; state.motion.ticks reaches returned target_tick"},"pose_solver":"existing lie26_rig.gd","collision":{"capsule_radius":Controller.RADIUS,"capsule_height":Controller.HEIGHT,"house_scale":Layout.HOUSE_SCALE,"source":"Authored master triangles plus four courtyard guards; collision only"}}}
static func serialize_parts(parts: Array) -> Array:
    var result: Array=[]
    for p in parts:
        var pose: Transform3D=p["pose"];result.append({"master":p["master"],"bone":p["bone"],"curve":p["curve"],"radius_scale":p["radius_scale"],"basis":[Rig.array(pose.basis.x),Rig.array(pose.basis.y),Rig.array(pose.basis.z)],"origin":Rig.array(pose.origin)})
    return result
func _exit_tree() -> void:
    if texture!=null:texture.texture_rd_rid=RID()
    if effect!=null:effect.shutdown()
