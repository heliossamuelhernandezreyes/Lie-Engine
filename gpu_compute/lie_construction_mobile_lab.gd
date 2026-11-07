extends "res://lie_hq_construction_lab.gd"
const Meter=preload("res://lie_construction_mobile_metrics.gd")
const Hardware=preload("res://lie_hardware_diagnostics.gd")
const APP_VERSION="6.0.0-construction-field"
var output_resolution: int=960
var hardware=Hardware.new()
var meter=Meter.new()
var busy: bool=false
var cancelled: bool=false
var _internal: bool=false
var _measuring: bool=false
var _last_frame: int=0
var _poll_clock: float=0.
var _status: Label
var _progress: Label
var _buttons: Array=[]
var _fingers: Dictionary={}
var _mouse_drag: bool=false
var _telemetry: Dictionary={}
var _latest: Dictionary={}
var _report_dialog: AcceptDialog
var _report_text: TextEdit
var _save_dialog: FileDialog
var _controls_scroll: ScrollContainer
var _quality: OptionButton
var _message: String=""

func _create_effect() -> CompositorEffect:return Effect.new(output_resolution)
func _create_field() -> CompositorEffect:
    var result: CompositorEffect=Field.new();result.profile_transport=true;return result
func _ready() -> void:
    state.yaw=-25.
    super._ready()
    if picture==null:_build_ui()
    var saved: Variant=JSON.parse_string(FileAccess.get_file_as_string("user://lie-construction-last.json")) if FileAccess.file_exists("user://lie-construction-last.json") else null
    if saved is Dictionary:_latest=saved
    RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
    _telemetry=hardware.telemetry();_poll_clock=.5
    _last_frame=Time.get_ticks_usec()
    _sync_control_availability()

func _label(parent: Node,text: String,size: int=19) -> Label:
    var label:=Label.new();label.text=text;label.add_theme_font_size_override("font_size",size);parent.add_child(label);return label
func _button(parent: Node,text: String,action: Callable,lock_during_test: bool=true) -> Button:
    var button:=Button.new();button.text=text;button.custom_minimum_size.y=48;button.pressed.connect(action);parent.add_child(button)
    if lock_during_test:_buttons.append(button)
    return button
func _slider(parent: Node,key: String,title: String,low: float,high: float,step: float=1.) -> void:
    _label(parent,title)
    var slider:=HSlider.new();slider.min_value=low;slider.max_value=high;slider.step=step;slider.custom_minimum_size=Vector2(300,44);slider.value=state[key]
    slider.value_changed.connect(func(value: float):command({"op":"set_values","values":{key:int(value) if key=="bounces" else value}}));parent.add_child(slider);controls[key]=slider
func _build_ui() -> void:
    var layer:=CanvasLayer.new();add_child(layer)
    var bg:=ColorRect.new();bg.color=Color(.03,.04,.055);bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layer.add_child(bg)
    var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,16)
    layer.add_child(margin)
    var columns:=HBoxContainer.new();columns.add_theme_constant_override("separation",16);margin.add_child(columns)
    var left:=VBoxContainer.new();left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;columns.add_child(left)
    _label(left,"LIE · Construcción v6",28)
    picture=TextureRect.new();picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.size_flags_vertical=Control.SIZE_EXPAND_FILL;picture.size_flags_horizontal=Control.SIZE_EXPAND_FILL;picture.mouse_filter=Control.MOUSE_FILTER_STOP;left.add_child(picture)
    _label(left,"Un dedo: girar · Dos dedos: acercar y desplazar",17)
    _status=_label(left,"Preparando capturas…",17);_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_status.custom_minimum_size.y=72
    _progress=_label(left,"",17);_progress.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    _controls_scroll=ScrollContainer.new();_controls_scroll.custom_minimum_size.x=352;_controls_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;columns.add_child(_controls_scroll)
    var box:=VBoxContainer.new();box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;box.add_theme_constant_override("separation",8);_controls_scroll.add_child(box)
    _label(box,"ESCENA Y CALIDAD",22)
    selector=OptionButton.new();selector.custom_minimum_size.y=48
    if effect!=null and effect.capture_loaded:
        for mode in effect.manifest.modes:selector.add_item(mode.replace("asset_","").replace("_"," "))
        selector.item_selected.connect(func(i: int):command({"op":"set_values","values":{"mode":effect.manifest.modes[i]}}))
    box.add_child(selector)
    var quality:=OptionButton.new();quality.custom_minimum_size.y=48;_quality=quality
    for size in [480,720,960]:quality.add_item("Salida %d · interna %d" % [size,size*2])
    quality.select([480,720,960].find(output_resolution));quality.item_selected.connect(func(i: int):command({"op":"set_resolution","value":[480,720,960][i]}));box.add_child(quality);_buttons.append(quality)
    _button(box,"Cambiar semilla 2102 / 7319",func():command({"op":"set_values","values":{"seed":7319 if state.seed==2102 else 2102}}))
    _button(box,"Centrar cámara",func():command({"op":"set_values","values":{"yaw":-25.,"elevation":22.,"zoom":1.,"focus_x":0.,"focus_y":0.}}))
    _label(box,"ILUMINACIÓN",22)
    for key in ["field_lighting","indirect","key_enabled","fill_enabled","energy_radius","normals","shadows"]:
        var checkbox:=CheckBox.new();checkbox.text={"field_lighting":"Campo LIE (desmarcado: referencia)","indirect":"Mostrar rebotes indirectos","key_enabled":"Luz principal","fill_enabled":"Segunda luz","energy_radius":"Radio energético","normals":"Relieve fino","shadows":"Sombras"}[key];checkbox.button_pressed=state[key];checkbox.custom_minimum_size.y=40;checkbox.toggled.connect(func(value: bool):command({"op":"set_values","values":{key:value}}));box.add_child(checkbox);controls[key]=checkbox
    for row in [["light","Dirección de la luz",-180.,180.,1.],["fill_power","Potencia de segunda luz",0.,2.,.01],["bounces","Rebotes calculados",0.,4.,1.],["ambient","Ambiente",0.,2.,.01],["door_angle","Apertura de puerta",0.,110.,1.]]:_slider(box,row[0],row[1],row[2],row[3],row[4])
    _label(box,"MEDICIONES",22)
    _button(box,"Comparar directa / 2 rebotes",func():run_comparison())
    _button(box,"Sesión de 60 segundos",func():run_session(60.))
    _button(box,"Sesión de 10 minutos",func():run_session(600.))
    _button(box,"Detener prueba",func():cancelled=true,false)
    _button(box,"Informe / copiar",_show_report,false)
    var note:=_label(box,"Mismas capturas y LOD de v5.\nLa resolución se elige explícitamente.\nReferencia: una luz; comparación: dos.\nPowered by Poly Haven\nLadrillo: Centre-of-Archaeology",15);note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    _report_dialog=AcceptDialog.new();_report_dialog.title="Informe LIE v6";_report_dialog.min_size=Vector2i(800,530);layer.add_child(_report_dialog)
    _report_text=TextEdit.new();_report_text.editable=false;_report_text.custom_minimum_size=Vector2(760,450);_report_dialog.add_child(_report_text)
    var copy:=_report_dialog.add_button("Copiar resumen",false,"copy");copy.custom_minimum_size.y=44
    _report_dialog.add_button("Guardar JSON completo",false,"save")
    _report_dialog.custom_action.connect(func(action: StringName):
        if action=="copy":DisplayServer.clipboard_set(_report_text.text)
        elif action=="save" and not busy and not _latest.is_empty():_save_dialog.popup_centered(Vector2i(900,600)))
    _save_dialog=FileDialog.new();_save_dialog.use_native_dialog=true;_save_dialog.access=FileDialog.ACCESS_FILESYSTEM;_save_dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE;_save_dialog.filters=PackedStringArray(["*.json ; Informe JSON ; application/json"]);_save_dialog.current_file="LIE-construccion-v6.json";layer.add_child(_save_dialog)
    _save_dialog.file_selected.connect(func(path: String):
        var file:=FileAccess.open(path,FileAccess.WRITE)
        if file==null:_progress.text="No se pudo guardar el informe en el destino elegido.";return
        file.store_string(JSON.stringify(_latest,"\t",true,true));file.close();_progress.text="Informe completo guardado.")

func command(request: Dictionary) -> Dictionary:
    if request.get("op")=="cancel_test":cancelled=true;return {"ok":true}
    if busy and not _internal and request.get("op")!="snapshot":return {"ok":false,"error":"measurement_in_progress"}
    if request.get("op")=="set_resolution":
        var size: Variant=request.get("value")
        if not size is int or size not in [480,720,960]:return {"ok":false,"error":"resolution"}
        if size==output_resolution:return {"ok":true,"revision":revision}
        var previous: CompositorEffect=effect
        if texture!=null:texture.texture_rd_rid=RID()
        picture.texture=null;texture=null;output_resolution=size;effect=_create_effect()
        world_environment.compositor.compositor_effects=[transport,effect] if transport!=null else [effect]
        previous.shutdown();revision+=1;update_scene();_quality.select([480,720,960].find(size));return {"ok":true,"revision":revision}
    var result: Dictionary=super.command(request)
    if result.get("ok",false):_sync_control_availability()
    return result
func _sync_control_availability() -> void:
    for key in ["indirect","key_enabled","fill_enabled","energy_radius","fill_power","bounces"]:
        if not controls.has(key):continue
        var enabled: bool=not busy and state.field_lighting
        if controls[key] is HSlider:controls[key].editable=enabled
        else:controls[key].disabled=not enabled
func _set_values(values: Dictionary) -> bool:
    _internal=true;var result: Dictionary=command({"op":"set_values","values":values});_internal=false;return result.ok

func touch(index: int,position: Vector2,pressed: bool) -> void:
    if not pressed:_fingers.erase(index);return
    if not busy and picture.get_global_rect().has_point(position):_fingers[index]=position
func drag(index: int,position: Vector2) -> void:
    if busy or not _fingers.has(index):return
    var previous: Vector2=_fingers[index];var delta: Vector2=position-previous
    if _fingers.size()==1:_set_values({"yaw":wrapf(state.yaw-delta.x*.25,-180,180),"elevation":clampf(state.elevation+delta.y*.2,-85,85)})
    elif _fingers.size()==2:
        var other: int=_fingers.keys()[0] if _fingers.keys()[1]==index else _fingers.keys()[1];var anchor: Vector2=_fingers[other];var before: float=previous.distance_to(anchor);var after: float=position.distance_to(anchor)
        _set_values({"zoom":clampf(state.zoom*before/maxf(after,1.),.25,2.),"focus_x":clampf(state.focus_x-delta.x*.0015,-3.,3.),"focus_y":clampf(state.focus_y+delta.y*.0015,-3.,3.)})
    _fingers[index]=position
func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:touch(event.index,event.position,event.pressed)
    elif event is InputEventScreenDrag:drag(event.index,event.position)
    elif event is InputEventMouseButton:
        if event.button_index==MOUSE_BUTTON_LEFT:
            _mouse_drag=event.pressed and picture.get_global_rect().has_point(event.position)
            touch(-1,event.position,_mouse_drag)
        elif event.pressed and picture.get_global_rect().has_point(event.position) and not busy and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:_set_values({"zoom":clampf(state.zoom*(.9 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.1),.25,2.)})
    elif event is InputEventMouseMotion and _mouse_drag:drag(-1,event.position)
func _notification(what: int) -> void:
    if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
        _fingers.clear();_mouse_drag=false
        if busy:cancelled=true

func _light_metrics() -> Dictionary:return transport.transport_metrics() if transport!=null else {}
func _light_owner() -> int:return transport.get_instance_id() if transport!=null else 0
func _process(delta: float) -> void:
    super._process(delta)
    var now: int=Time.get_ticks_usec()
    if _measuring:meter.add_frame(float(now-_last_frame)/1000.)
    _last_frame=now;_poll_clock+=delta
    if _measuring:meter.collect(effect.diagnostics(),_light_owner(),_light_metrics())
    if _poll_clock<.5:return
    _poll_clock=0.;effect.request_diagnostics();var a: Dictionary=effect.diagnostics();_telemetry=hardware.telemetry()
    var total: int=int(a.get("allocation_bytes",0))+int(a.get("field",{}).get("bytes",0));var rss: Dictionary=_telemetry.get("process_memory",{}).get("rss",{})
    _status.text="Pantalla %d FPS · salida %d / interna %d\nRecursos LIE %.1f MiB · RSS %s\n%s" % [Engine.get_frames_per_second(),output_resolution,output_resolution*2,total/1048576.,("%.1f MiB" % (float(rss.bytes)/1048576.)) if rss.get("available",false) else "no disponible",str(metrics.get("error",a.get("failure","")))]
    if busy:_progress.text=_message

func _sync_metrics() -> Dictionary:
    var requested: int=Time.get_ticks_usec();effect.request_diagnostics()
    for i in range(1200):
        await get_tree().process_frame
        var result: Dictionary=effect.diagnostics()
        if int(result.get("snapshot_usec",0))>=requested:return result
    return {}
func _warm_up() -> Dictionary:
    var before: int=Time.get_ticks_usec()
    for i in range(8):await get_tree().process_frame
    return {"elapsed_ms":float(Time.get_ticks_usec()-before)/1000.,"resources":await _sync_metrics()}
func _block_start() -> Dictionary:
    var a: Dictionary=await _sync_metrics();meter.begin(a,_light_owner(),_light_metrics());_last_frame=Time.get_ticks_usec();_measuring=true
    return {"state":state.duplicate(),"resources":a,"telemetry":hardware.telemetry(),"start_usec":Time.get_ticks_usec()}
func _block_end(before: Dictionary,kind: String) -> Dictionary:
    _measuring=false
    for i in range(6):await get_tree().process_frame
    var a: Dictionary=await _sync_metrics();meter.collect(a,_light_owner(),_light_metrics())
    return {"kind":kind,"before":before,"after":{"resources":a,"telemetry":hardware.telemetry(),"end_usec":Time.get_ticks_usec()},"measurements":meter.result()}
func _wait_image(previous: int) -> bool:
    for i in range(1200):
        await get_tree().process_frame
        if effect.frame_count>previous:return true
        if cancelled:return false
    return false
func _lock_controls(value: bool) -> void:
    for button in _buttons:button.disabled=value
    selector.disabled=value
    for control in controls.values():
        if control is HSlider:control.editable=not value
        elif control is BaseButton:control.disabled=value
    _fingers.clear();_mouse_drag=false
    _sync_control_availability()
func _new_report(kind: String) -> Dictionary:
    return {"schema":"lie-construction-mobile-report/1","version":APP_VERSION,"kind":kind,"started_at":Time.get_datetime_string_from_system(),"device":OS.get_model_name(),"os":OS.get_name(),"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info(),"scene_identity":effect.manifest.get("scene_identity",""),"output_size":output_resolution,"internal_size":output_resolution*2,"blocks":[],"warm_up":[],"cancelled":false,"error":"","complete":false,"physical_android_session":OS.has_feature("android"),"scope":"Measurements from this runtime only. Software Vulkan is not Android performance. Resource accounting excludes driver/cache/CPU allocations. RSS and PSS are separate process metrics, not dedicated GPU memory. Temperature is reported only when an explicitly named GPU sensor is readable."}
func _persist_report() -> void:
    var file:=FileAccess.open("user://lie-construction-last.json",FileAccess.WRITE)
    if file!=null:file.store_string(JSON.stringify(_latest,"\t",true,true));file.close()
func _finish(backup: Dictionary) -> void:
    _measuring=false;_latest.cancelled=cancelled;_latest.restored=_set_values(backup);_latest.complete=not cancelled and _latest.error.is_empty();_latest.finished_at=Time.get_datetime_string_from_system();busy=false;_lock_controls(false);_persist_report()
    _progress.text="Prueba detenida; ajustes restaurados. Informe disponible." if cancelled else "Prueba terminada; ajustes restaurados. Abre Informe." if _latest.complete else "Prueba incompleta: "+_latest.error
func run_comparison(events: int=24) -> void:
    if busy or not metrics.get("configured",false):return
    busy=true;cancelled=false;_lock_controls(true);var backup: Dictionary=state.duplicate();_latest=_new_report("paired_direct_vs_two_bounces")
    for indirect in [false,true]:
        if cancelled:break
        _message="Preparando "+("dos rebotes" if indirect else "directa sin rebotes")
        if not _set_values({"field_lighting":true,"indirect":indirect,"bounces":2 if indirect else 0}):_latest.error="lighting_configuration";break
        _latest.warm_up.append(await _warm_up())
        for kind in ["camera","light"]:
            if cancelled:break
            var before: Dictionary=await _block_start()
            for i in range(events):
                if cancelled:break
                _message="%s · %s · %d/%d" % ["Dos rebotes" if indirect else "Directa",kind,i+1,events]
                var frames_before: int=effect.frame_count;var start: int=Time.get_ticks_usec();var values: Dictionary={"yaw":wrapf(float(backup.yaw)+sin(float(i+1)*.37)*18.,-180,180)} if kind=="camera" else {"light":wrapf(float(backup.light)+sin(float(i+1)*.43)*30.,-180,180)}
                if not _set_values(values):_latest.error="event_configuration";break
                meter.add_command(float(Time.get_ticks_usec()-start)/1000.)
                if not await _wait_image(frames_before):
                    if not cancelled:_latest.error="image_dispatch_timeout"
                    break
            _latest.blocks.append(await _block_end(before,kind));_persist_report()
            if not _latest.error.is_empty():break
        if not _latest.error.is_empty():break
        _set_values({"yaw":backup.yaw,"light":backup.light})
    _finish(backup)
func run_session(seconds: float=60.) -> void:
    if busy or not metrics.get("configured",false) or seconds<=0 or seconds>600:return
    busy=true;cancelled=false;_lock_controls(true);var backup: Dictionary=state.duplicate();_latest=_new_report("sustained_camera_light_idle");_latest.requested_seconds=seconds;_latest.warm_up.append(await _warm_up())
    var start: int=Time.get_ticks_usec();var index: int=0
    while not cancelled and float(Time.get_ticks_usec()-start)/1e6<seconds:
        var kind: String=["camera","light","idle"][index%3];var before: Dictionary=await _block_start();var block_start: int=Time.get_ticks_usec()
        while not cancelled and float(Time.get_ticks_usec()-block_start)/1e6<10. and float(Time.get_ticks_usec()-start)/1e6<seconds:
            var elapsed: float=float(Time.get_ticks_usec()-start)/1e6;_message="Sesión %.0f / %.0f s · %s" % [elapsed,seconds,kind]
            if kind!="idle":
                var frame_before: int=effect.frame_count;var t: int=Time.get_ticks_usec();_set_values({"yaw":wrapf(float(backup.yaw)+sin(elapsed*.35)*25.,-180,180)} if kind=="camera" else {"light":wrapf(float(backup.light)+sin(elapsed*.5)*45.,-180,180)});meter.add_command(float(Time.get_ticks_usec()-t)/1000.)
                if not await _wait_image(frame_before):
                    if not cancelled:_latest.error="image_dispatch_timeout"
                    break
            else:await get_tree().process_frame
        _latest.blocks.append(await _block_end(before,kind));_persist_report();index+=1
        if not _latest.error.is_empty():break
    _latest.elapsed_seconds=float(Time.get_ticks_usec()-start)/1e6;_finish(backup)
func portable_report() -> Dictionary:
    var result: Dictionary=_latest.duplicate(true)
    for block in result.get("blocks",[]):
        block.measurements.erase("appearance_rows");block.measurements.erase("lighting_rows")
        for side in ["before","after"]:block[side].resources.erase("profile")
    for warm in result.get("warm_up",[]):warm.resources.erase("profile")
    result.copy_scope="Summary with percentiles and resource/thermal boundaries; export the complete JSON for raw GPU interval rows."
    return result
func _show_report() -> void:
    _report_text.text=JSON.stringify(portable_report(),"\t",true,true) if not _latest.is_empty() else "Primero ejecuta una medición. Los datos se guardan en el dispositivo; no se envían automáticamente."
    _report_dialog.popup_centered(Vector2i(900,600))
