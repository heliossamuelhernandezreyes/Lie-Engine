extends Node3D
const Doc=preload("res://workshop/lie_document.gd")
const Collision=preload("res://workshop/lie_collision.gd")
const SceneModel=preload("res://workshop/lie_scene_model.gd")
const Capture=preload("res://lie18_capture_effect.gd")
const Lighting=preload("res://lie18_light_effect.gd")
const Optics=preload("res://lie18_optics_effect.gd")
var document:=Doc.new()
var effect: CompositorEffect
var lighting: CompositorEffect
var optics: CompositorEffect
var camera: Camera3D
var model: Dictionary={}
var evaluated: Dictionary={}
var ui: CanvasLayer
var selected: String="torso"
var part_list: ItemList
var parent_choice: OptionButton
var parent_ids: Array=[]
var material_choice: OptionButton
var title_label: Label
var status: Label
var command_result: Label
var command_editor: TextEdit
var fields: Dictionary={}
var material_controls: Dictionary={}
var setting_controls: Dictionary={}
var color_control: ColorPickerButton
var light_slider: HSlider
var fluid_choice: OptionButton
var angle_slider: HSlider
var timeline: HSlider
var play_button: Button
var _bodies: Dictionary={}
var _dragging: bool=false
var _drag_piece: bool=false
var _drag_plane:=Plane()
var _drag_offset:=Vector3.ZERO
var _yaw: float=24
var _elevation: float=10
var _distance: float=4.1
var _fluid_time: float=0
var _poll_time: float=0
var _model_key: String=""
var _last_instance_bytes:=PackedByteArray()
var _part_serial: int=1
var last_command: Dictionary={}
var last_collisions: Array=[]
var profiling: bool=false
var metrics_label: Label
var profile_control: CheckBox
var _metrics_time: float=0
var _apply_state_us: int=0

func _ready() -> void:
    get_window().size=Vector2i(1280,800)
    effect=Capture.new(384)
    if not bool(effect.get("capture_loaded")):
        _build_ui(); status.text="Prepara los maestros antes de abrir el taller.\n"+str(effect.get("failure")); return
    lighting=Lighting.new(); optics=Optics.new()
    effect.set("lighting",lighting); optics.set("capture",effect); optics.set("lighting",lighting)
    var environment:=Environment.new()
    environment.background_mode=Environment.BG_COLOR
    environment.background_color=Color(.016,.024,.038)
    var world:=WorldEnvironment.new(); world.environment=environment
    var compositor:=Compositor.new(); compositor.compositor_effects=[lighting,effect,optics]
    world.compositor=compositor; add_child(world)
    camera=Camera3D.new(); camera.current=true; camera.fov=55; camera.near=.1; camera.far=100; add_child(camera)
    move_camera(); _build_ui(); _apply_state(true); _refresh_ui()
    DirAccess.make_dir_recursive_absolute("user://workshop")

func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("op") in ["runtime_profile","runtime_metrics"]:
        if request.has("expected_revision") and request["expected_revision"]!=document.revision: return {"ok":false,"error":"revision_conflict","revision":document.revision}
        if request["op"]=="runtime_profile":
            if not request.get("enabled") is bool: return {"ok":false,"error":"profiling_boolean"}
            profiling=request["enabled"]
            if profile_control!=null: profile_control.set_pressed_no_signal(profiling)
            if effect!=null: effect.set("profile_enabled",profiling)
            if lighting!=null: lighting.set("profile_enabled",profiling)
        return {"ok":true,"revision":document.revision,"metrics":runtime_metrics()}
    var before: Dictionary=document.state.duplicate(true)
    var response: Dictionary=document.dispatch(request)
    last_command=response.duplicate(true)
    if response.get("ok",false):
        var requests: Array=request.get("commands",[]) if request.get("op")=="batch" else [request]
        if requests.any(func(item: Variant): return item is Dictionary and item.get("op") in ["set_time","load_document"]):
            _fluid_time=float(document.state["time"])
        _apply_state(before["pieces"]!=document.state["pieces"])
        _refresh_ui()
    if command_result!=null: command_result.text="Cambio aplicado · revisión %d" % document.revision if response.get("ok",false) else "No aplicado: "+str(response.get("error"))
    return response

func agent_snapshot() -> Dictionary:
    var data: Dictionary=document.snapshot()
    data["collisions"]=last_collisions.duplicate(true)
    data["capture_loaded"]=effect!=null and bool(effect.get("capture_loaded"))
    data["visible_source_meshes"]=0
    data["selected_piece"]=selected
    data["inbox"]=OS.get_user_data_dir()+"/workshop/inbox.json"
    data["outbox"]=OS.get_user_data_dir()+"/workshop/outbox.json"
    data["runtime_commands"]=["runtime_profile","runtime_metrics"]
    data["metrics"]=runtime_metrics()
    return data

func runtime_metrics() -> Dictionary:
    return {"profiling":profiling,"cpu_apply_state_us_latest":_apply_state_us,
        "lighting":lighting.call("metrics") if lighting!=null else {},
        "consumer_profile":effect.call("profiling_snapshot") if effect!=null else [],
        "consumer_bytes":effect.get("allocation_bytes") if effect!=null else 0,
        "render_resolution":effect.get("render_size") if effect!=null else 0,
        "note":"GPU timestamps include only Lie passes; optics and Godot frame time are not included."}

func _apply_state(rebuild: bool=false) -> void:
    if camera==null: return
    var started: int=Time.get_ticks_usec()
    evaluated=Doc.evaluate(document.state)
    _yaw=float(document.state["camera"]["yaw_deg"]); _elevation=float(document.state["camera"]["elevation_deg"]); _distance=float(document.state["camera"]["distance"])
    move_camera()
    var next: Dictionary=SceneModel.build(document.state,evaluated,effect.get("masters"))
    # Static geometry/light codes remain resident. There is no repeated CPU
    # pair-visibility graph, and idle frames do not re-run transport.
    var key: String=next["signature"]
    var instances: PackedByteArray=next["instance_bytes"]
    if key!=_model_key or instances!=_last_instance_bytes:
        model=next; lighting.call("configure_workshop",model); _model_key=key; _last_instance_bytes=instances
    effect.call("configure_quality",document.state["settings"]["adaptive"],document.state["settings"]["temporal"],true,document.state["settings"]["temporal"])
    effect.call("set_edge_aa",document.state["settings"]["edges"])
    if rebuild: _rebuild_bodies()
    _update_bodies(); _update_optics()
    last_collisions=Collision.diagnostics(document.state,evaluated)
    if status!=null:
        status.text="%d piezas · 2 maestros compartidos\n%d contactos por revisar" % [document.state["pieces"].size(),last_collisions.size()]
    _apply_state_us=Time.get_ticks_usec()-started

func _rebuild_bodies() -> void:
    for body in _bodies.values(): remove_child(body); body.queue_free()
    _bodies.clear()
    for p in document.state["pieces"]:
        var body:=AnimatableBody3D.new(); body.name="Collider_"+p["id"]
        body.sync_to_physics=false
        var collision:=CollisionShape3D.new(); collision.shape=BoxShape3D.new(); body.add_child(collision)
        add_child(body); _bodies[p["id"]]=body

func _update_bodies() -> void:
    for p in document.state["pieces"]:
        if not _bodies.has(p["id"]): continue
        var pose: Transform3D=evaluated["poses"][p["id"]]
        var body: AnimatableBody3D=_bodies[p["id"]]
        body.transform=Transform3D(pose.basis.orthonormalized(),pose.origin)
        ((body.get_child(0) as CollisionShape3D).shape as BoxShape3D).size=pose.basis.get_scale()

func _update_optics() -> void:
    if optics==null or camera==null: return
    var sheets: Array=Collision.optical_sheets(document.state,_fluid_time,camera.global_transform,evaluated.get("poses",{}))
    optics.call("configure_optics",sheets,_fluid_time)

func _physics_process(delta: float) -> void:
    if camera==null: return
    if bool(document.state["playing"]):
        document.state["time"]=fposmod(float(document.state["time"])+delta,float(document.state["duration"]))
        _apply_state()
        if timeline!=null: timeline.set_value_no_signal(float(document.state["time"]))
    if document.state["settings"]["fluid"]!="off": _fluid_time+=delta; _update_optics()

func _process(delta: float) -> void:
    _poll_time+=delta
    if _poll_time>=.2: _poll_time=0; _poll_agent()
    _metrics_time+=delta
    if _metrics_time>=1 and metrics_label!=null:
        _metrics_time=0
        var values: Dictionary=runtime_metrics(); var light: Dictionary=values["lighting"]
        var timings: Array=values["consumer_profile"].map(func(row: Dictionary): return float(row["consumer_gpu_ns"])/1000000)
        timings.sort()
        metrics_label.text="Grafos %d · reutilizados %d\n" % [light.get("graph_rebuilds",0),light.get("graph_reuses",0)]+("Lie: %.1f ms · GPU local" % timings[int(timings.size()/2)] if profiling and not timings.is_empty() else "Midiendo…" if profiling else "Medición GPU desactivada")

func _poll_agent() -> void:
    var path: String="user://workshop/inbox.json"
    if not FileAccess.file_exists(path): return
    var file:=FileAccess.open(path,FileAccess.READ)
    if file==null or file.get_length()>1024*1024: return
    var request: Variant=JSON.parse_string(file.get_as_text()); file.close()
    var request_id: Variant=request.get("request_id") if request is Dictionary else null
    if request is Dictionary and request.has("request"):
        request=request["request"]
    DirAccess.remove_absolute(path)
    var result: Dictionary=command(request)
    var output:=FileAccess.open("user://workshop/outbox.json.tmp",FileAccess.WRITE)
    if output==null: return
    output.store_string(JSON.stringify({"request_id":request_id,"result":result,"snapshot":agent_snapshot()},"  ",true,true)); output.close()
    DirAccess.rename_absolute("user://workshop/outbox.json.tmp","user://workshop/outbox.json")

func move_camera() -> void:
    if camera==null: return
    var y: float=deg_to_rad(_yaw); var e: float=deg_to_rad(_elevation)
    var target:=Vector3(0,.25,0)
    camera.position=target+Vector3(sin(y)*cos(e),sin(e),cos(y)*cos(e))*_distance
    camera.look_at(target); _update_optics()

func _label(parent: Node,text: String,size: int=14) -> Label:
    var label:=Label.new(); label.text=text; label.add_theme_font_size_override("font_size",size); parent.add_child(label); return label
func _button(parent: Node,text: String,callback: Callable) -> Button:
    var button:=Button.new(); button.text=text; button.pressed.connect(callback); parent.add_child(button); return button
func _panel(position: Vector2,size: Vector2) -> VBoxContainer:
    var panel:=PanelContainer.new(); panel.position=position; panel.size=size
    var style:=StyleBoxFlat.new(); style.bg_color=Color(.035,.047,.068,.97); style.corner_radius_top_left=12; style.corner_radius_top_right=12; style.corner_radius_bottom_left=12; style.corner_radius_bottom_right=12
    for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: style.set_content_margin(side,14)
    panel.add_theme_stylebox_override("panel",style); ui.add_child(panel)
    var box:=VBoxContainer.new(); box.add_theme_constant_override("separation",8)
    if position.x>1000:
        var scroll:=ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
        scroll.custom_minimum_size=Vector2(220,660); panel.add_child(scroll)
        box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(box)
    else: panel.add_child(box)
    return box

func _build_ui() -> void:
    ui=CanvasLayer.new(); add_child(ui)
    var top:=HBoxContainer.new(); top.position=Vector2(20,16); ui.add_child(top)
    _label(top,"LIE",28).add_theme_color_override("font_color",Color(.25,.85,1))
    _label(top,"  Taller de piezas",24)
    var left: VBoxContainer=_panel(Vector2(16,68),Vector2(248,694))
    _label(left,"BIBLIOTECA",13).add_theme_color_override("font_color",Color(.5,.65,.8))
    _label(left,"Una pieza, muchas creaciones",15)
    var add_row:=HBoxContainer.new(); left.add_child(add_row)
    _button(add_row,"Bloque",_add_piece.bind("box",false)); _button(add_row,"Chapa",_add_piece.bind("box",true)); _button(add_row,"Cilindro",_add_piece.bind("cylinder",false))
    _label(left,"ENSAMBLAJE",13)
    part_list=ItemList.new(); part_list.custom_minimum_size=Vector2(214,260); part_list.size_flags_vertical=Control.SIZE_EXPAND_FILL
    part_list.item_selected.connect(_select_part); left.add_child(part_list)
    var edits:=HBoxContainer.new(); left.add_child(edits)
    _button(edits,"Duplicar",_duplicate); _button(edits,"Eliminar",func(): command({"op":"remove_piece","id":selected}))
    var history:=HBoxContainer.new(); left.add_child(history)
    _button(history,"Deshacer",func(): command({"op":"undo"})); _button(history,"Rehacer",func(): command({"op":"redo"}))
    var storage:=HBoxContainer.new(); left.add_child(storage)
    _button(storage,"Guardar",func(): var r: Dictionary=command({"op":"save_document"}); if r["ok"]: command_result.text="Robot guardado")
    _button(storage,"Abrir",func(): command({"op":"load_document"}))
    status=_label(left,"Preparando maestros…",13)
    var meter:=CheckBox.new(); profile_control=meter; meter.text="Medir renderizado"; left.add_child(meter)
    meter.toggled.connect(func(value: bool): command({"op":"runtime_profile","enabled":value}))
    metrics_label=_label(left,"Medición GPU desactivada",11)
    _label(left,"Arrastra el fondo para orbitar.\nRueda: acercar · Espacio: animar",12)
    var right: VBoxContainer=_panel(Vector2(1016,68),Vector2(248,694))
    title_label=_label(right,"PIEZA",18); title_label.clip_text=true
    parent_choice=OptionButton.new(); parent_choice.fit_to_longest_item=false; parent_choice.item_selected.connect(_set_parent); right.add_child(parent_choice)
    _button(right,"Acoplar caras",_snap)
    for field in ["position","scale","rotation_deg"]:
        _label(right,{"position":"Posición de articulación","scale":"Tamaño de pieza","rotation_deg":"Orientación"}[field],12)
        var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",4); right.add_child(row); fields[field]=[]
        for axis in range(3):
            var spin:=SpinBox.new(); spin.min_value=.02 if field=="scale" else -360 if field=="rotation_deg" else -10
            spin.max_value=5 if field=="scale" else 360 if field=="rotation_deg" else 10
            spin.step=1 if field=="rotation_deg" else .01; spin.custom_minimum_size=Vector2(60,28); spin.size_flags_horizontal=Control.SIZE_EXPAND_FILL
            spin.get_line_edit().add_theme_font_size_override("font_size",12); spin.get_line_edit().add_theme_constant_override("minimum_character_width",3); spin.tooltip_text=["X","Y","Z"][axis]
            spin.value_changed.connect(_edit_vector.bind(field,axis)); row.add_child(spin); fields[field].append(spin)
    material_choice=OptionButton.new(); material_choice.item_selected.connect(_set_material); right.add_child(material_choice)
    var color:=ColorPickerButton.new(); color_control=color; color.text="Color del material"; color.color=Color(.62,.78,.95).linear_to_srgb(); right.add_child(color)
    color.color_changed.connect(func(value: Color): var c: Color=value.srgb_to_linear(); command({"op":"set_material","name":_selected_piece()["material"],"values":{"tint_linear":[c.r,c.g,c.b]}}))
    for field in ["roughness","metallic"]:
        _label(right,"Rugosidad" if field=="roughness" else "Metal",12)
        var slider:=HSlider.new(); slider.min_value=0; slider.max_value=1; slider.step=.01; slider.value=.34 if field=="roughness" else .85
        slider.value_changed.connect(_edit_material.bind(field)); material_controls[field]=slider; right.add_child(slider)
    _label(right,"Pose manual de articulación",12)
    angle_slider=HSlider.new(); angle_slider.custom_minimum_size=Vector2(200,24)
    angle_slider.value_changed.connect(_set_angle); right.add_child(angle_slider)
    _button(right,"Registrar clave",_record_key).tooltip_text="Añade o actualiza la clave del tiempo actual; conserva las demás."
    _label(right,"ILUMINACIÓN Y SUPERFICIES",12)
    var lamp:=HSlider.new(); light_slider=lamp; lamp.min_value=-2; lamp.max_value=2; lamp.step=.02; lamp.value=-1.7; right.add_child(lamp)
    lamp.value_changed.connect(func(value: float): var position: Array=document.state["lights"][0]["position"].duplicate(); position[0]=value; command({"op":"set_light","index":0,"values":{"position":position}}))
    for pair in [["Rebote de luz","bounces"],["Historial temporal","temporal"],["Suavizar contornos","edges"]]:
        var toggle:=CheckBox.new(); toggle.text=pair[0]; toggle.button_pressed=true
        toggle.toggled.connect(_toggle_setting.bind(pair[1])); setting_controls[pair[1]]=toggle; right.add_child(toggle)
    var fluid:=OptionButton.new(); fluid_choice=fluid; for text in ["Sin fluido","Agua con ondas","Lluvia"]: fluid.add_item(text)
    fluid.item_selected.connect(func(index: int): command({"op":"set_settings","values":{"fluid":["off","water","rain"][index]}})); right.add_child(fluid)
    _label(right,"Agua visual · gotas con gravedad\nColisión aproximada por cajas",11)
    var bottom: VBoxContainer=_panel(Vector2(280,640),Vector2(720,124))
    var playback:=HBoxContainer.new(); bottom.add_child(playback)
    play_button=_button(playback,"Reproducir",func(): command({"op":"set_playing","value":not document.state["playing"]}))
    _label(playback,"  Animación · claves de articulaciones",14)
    timeline=HSlider.new(); timeline.min_value=0; timeline.max_value=2; timeline.step=.01
    timeline.value_changed.connect(func(value: float): command({"op":"set_time","value":value})); bottom.add_child(timeline)
    command_result=_label(bottom,"Controles visuales y comandos comparten el mismo documento.",12)
    var api_button: Button=_button(top,"   Comandos   ",_show_commands); api_button.position=Vector2(600,0)

func _refresh_ui() -> void:
    if part_list==null: return
    if Doc.index_of(document.state,selected)<0: selected=document.state["pieces"][0]["id"]
    part_list.clear()
    for p in document.state["pieces"]:
        part_list.add_item(p["id"]+"  ·  "+("cilindro" if p["master"]=="cylinder" else "chapa/bloque"))
        if p["id"]==selected: part_list.select(part_list.item_count-1)
    var piece: Dictionary=_selected_piece()
    title_label.text=selected
    for field in fields:
        for axis in range(3): (fields[field][axis] as SpinBox).set_value_no_signal(float(piece[field][axis]))
    parent_choice.clear(); parent_ids=[""]; parent_choice.add_item("Sin padre")
    for p in document.state["pieces"]:
        if p["id"]==selected: continue
        parent_ids.append(p["id"]); parent_choice.add_item("Padre: "+p["id"])
    parent_choice.select(parent_ids.find(piece["parent"]))
    material_choice.clear()
    for name in document.state["materials"]: material_choice.add_item(name)
    material_choice.select(document.state["materials"].keys().find(piece["material"]))
    var material: Dictionary=document.state["materials"][piece["material"]]
    var tint: Vector3=Doc.vec(material["tint_linear"])
    color_control.color=Color(tint.x,tint.y,tint.z).linear_to_srgb()
    for field in material_controls: (material_controls[field] as HSlider).set_value_no_signal(float(material[field]))
    light_slider.set_value_no_signal(float(document.state["lights"][0]["position"][0]))
    for field in setting_controls:
        (setting_controls[field] as CheckBox).set_pressed_no_signal(int(document.state["settings"][field])>0 if field=="bounces" else bool(document.state["settings"][field]))
    fluid_choice.select(["off","water","rain"].find(document.state["settings"]["fluid"]))
    angle_slider.min_value=float(piece["limits_deg"][0]); angle_slider.max_value=float(piece["limits_deg"][1])
    angle_slider.set_value_no_signal(Doc.track_angle(document.state["tracks"].get(selected,[]),float(document.state["time"]),float(piece["angle_deg"])))
    timeline.max_value=float(document.state["duration"])
    timeline.set_value_no_signal(float(document.state["time"]))
    play_button.text="Pausar" if document.state["playing"] else "Reproducir"

func _selected_piece() -> Dictionary:
    return document.state["pieces"][Doc.index_of(document.state,selected)]
func _select_part(index: int) -> void:
    selected=document.state["pieces"][index]["id"]; _refresh_ui()
func _new_id(prefix: String) -> String:
    while Doc.index_of(document.state,prefix+str(_part_serial))>=0: _part_serial+=1
    var id: String=prefix+str(_part_serial); _part_serial+=1; return id
func _add_piece(master: String,plate: bool) -> void:
    var id: String=_new_id("pieza_")
    var result: Dictionary=command({"op":"add_piece","id":id,"values":{"master":master,"position":[1.1,.65,0],"scale":[.55,.07,.35] if plate else [.28,.55,.28] if master=="cylinder" else [.35,.35,.35]}})
    if result["ok"]: selected=id; _refresh_ui()
func _duplicate() -> void:
    var id: String=_new_id("copia_")
    var position: Array=_selected_piece()["position"].duplicate(); position[0]=float(position[0])+.35
    var result: Dictionary=command({"op":"duplicate_piece","id":id,"source":selected,"values":{"position":position}})
    if result["ok"]: selected=id; _refresh_ui()
func _edit_vector(value: float,field: String,axis: int) -> void:
    var vector: Array=_selected_piece()[field].duplicate(); vector[axis]=value
    command({"op":"update_piece","id":selected,"values":{field:vector}})
func _edit_material(value: float,field: String) -> void:
    command({"op":"set_material","name":_selected_piece()["material"],"values":{field:value}})
func _set_material(index: int) -> void:
    command({"op":"update_piece","id":selected,"values":{"material":document.state["materials"].keys()[index]}})
func _set_parent(index: int) -> void:
    if evaluated.is_empty(): return
    var parent: String=parent_ids[index]
    var current: Transform3D=evaluated["joints"][selected]
    var local: Transform3D=current if parent=="" else (evaluated["joints"][parent] as Transform3D).affine_inverse()*current
    command({"op":"batch","commands":[{"op":"set_track","id":selected,"keys":[]},{"op":"update_piece","id":selected,"values":{"parent":parent,"position":Doc.arr(local.origin),"rotation_deg":Doc.arr(local.basis.get_euler()*180/PI),"angle_deg":0}}]})
func _snap() -> void:
    var p: Dictionary=_selected_piece()
    if p["parent"]=="": command_result.text="Elige un padre para acoplar la pieza."; return
    var parent: Dictionary=document.state["pieces"][Doc.index_of(document.state,p["parent"])]
    var basis: Basis=Basis.from_euler(Doc.vec(p["rotation_deg"])*PI/180)*Basis(Doc.vec(p["axis"]),deg_to_rad(float(p["angle_deg"])))
    var position: Vector3=Doc.vec(parent["offset"])-Vector3.UP*float(parent["scale"][1])*.5-basis*(Doc.vec(p["offset"])+Vector3.UP*float(p["scale"][1])*.5)
    command({"op":"update_piece","id":selected,"values":{"position":Doc.arr(position)}})
func _set_angle(value: float) -> void:
    var requests: Array=[{"op":"update_piece","id":selected,"values":{"angle_deg":value}},{"op":"set_playing","value":false}]
    if not document.state["tracks"].get(selected,[]).is_empty():
        requests.append({"op":"set_key","id":selected,"time":document.state["time"],"angle_deg":value})
    command({"op":"batch","commands":requests})
func _record_key() -> void:
    command({"op":"set_key","id":selected,"time":document.state["time"],"angle_deg":angle_slider.value})
func _toggle_setting(value: bool,field: String) -> void:
    command({"op":"set_settings","values":{field:(2 if value else 0) if field=="bounces" else value}})

func _show_commands() -> void:
    var dialog:=Window.new(); dialog.title="Comandos de Lie"; dialog.size=Vector2i(650,450); dialog.exclusive=true
    var box:=VBoxContainer.new(); box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); dialog.add_child(box)
    _label(box,"La API aplica las mismas validaciones que los controles.",14)
    command_editor=TextEdit.new(); command_editor.size_flags_vertical=Control.SIZE_EXPAND_FILL
    command_editor.text=JSON.stringify({"op":"update_piece","id":selected,"values":{"material":"steel"}},"  "); box.add_child(command_editor)
    _button(box,"Ejecutar comando",func(): command(JSON.parse_string(command_editor.text)))
    dialog.close_requested.connect(dialog.queue_free); add_child(dialog); dialog.popup_centered()

func _pick(position: Vector2) -> String:
    var origin: Vector3=camera.project_ray_origin(position)
    var endpoint: Vector3=origin+camera.project_ray_normal(position)*100
    var closest: float=INF; var picked: String=""
    for id in evaluated["poses"]:
        var pose: Transform3D=evaluated["poses"][id]
        var inv: Transform3D=pose.affine_inverse()
        var p: Vector3=inv*origin; var d: Vector3=inv*endpoint-p
        var lo: float=0; var hi: float=1
        for axis in range(3):
            if absf(d[axis])<1e-10:
                if absf(p[axis])>.5: lo=2; break
            else:
                var a: float=(-.5-p[axis])/d[axis]; var b: float=(.5-p[axis])/d[axis]
                lo=maxf(lo,minf(a,b)); hi=minf(hi,maxf(a,b))
        if lo<=hi and lo<closest: closest=lo; picked=id
    return picked

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_SPACE: command({"op":"set_playing","value":not document.state["playing"]})
    if event is InputEventMouseButton:
        if event.button_index==MOUSE_BUTTON_LEFT:
            _dragging=event.pressed; _drag_piece=false
            if event.pressed and camera!=null:
                var id: String=_pick(event.position)
                if id!="":
                    selected=id; _refresh_ui(); command({"op":"set_playing","value":false}); _drag_piece=true
                    var origin: Vector3=(evaluated["joints"][id] as Transform3D).origin
                    _drag_plane=Plane(camera.global_basis.z,origin)
                    var hit: Variant=_drag_plane.intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
                    _drag_offset=origin-hit if hit is Vector3 else Vector3.ZERO
        if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
            command({"op":"set_camera","values":{"distance":clampf(_distance*(.9 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.1),2.5,7)}})
    if event is InputEventMouseMotion and _dragging:
        if _drag_piece:
            var hit: Variant=_drag_plane.intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
            if hit is Vector3:
                var p: Dictionary=_selected_piece()
                var world: Vector3=hit+_drag_offset
                var position: Vector3=world if p["parent"]=="" else (evaluated["joints"][p["parent"]] as Transform3D).affine_inverse()*world
                command({"op":"update_piece","id":selected,"values":{"position":Doc.arr(position)}})
        else:
            command({"op":"set_camera","values":{"yaw_deg":wrapf(_yaw-event.relative.x*.3,-180,180),"elevation_deg":clampf(_elevation+event.relative.y*.3,-65,75)}})

func _exit_tree() -> void:
    for item in [optics,effect,lighting]:
        if item!=null: item.call("shutdown")
