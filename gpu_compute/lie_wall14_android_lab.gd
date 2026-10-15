extends "res://lie_wall13_android_lab.gd"
const Diagnostics=preload("res://lie_mobile_diagnostics.gd")
var _touches: Dictionary={}
var _mouse_dragging: bool=false
var _drag_delta:=Vector2.ZERO
var _zoom_ratio: float=1.
var _report_dialog: PanelContainer
var _report_text: TextEdit
var _report_feedback: Label
var _diagnostic_label: Label
var _live_clock: float=0.
var _cpu_applies: Array=[]
var _frame_rows: Array=[]
var _diagnostic_report: Dictionary={}
var _copy_busy: bool=false
var _report_content: String=""
var _gesture_changes: int=0
func _apply() -> void:
    var begin: int=Time.get_ticks_usec();super._apply()
    _cpu_applies.append({"revision":revision,"elapsed_ms":float(Time.get_ticks_usec()-begin)/1000.})
    if _cpu_applies.size()>240:_cpu_applies.pop_front()
func command(request: Variant) -> Dictionary:
    if request is Dictionary:
        var op: String=str(request.get("op",""))
        if op in ["diagnostic_report","diagnose"]:
            if request.size()!=1:return {"ok":false,"error":"diagnostic_fields","revision":revision}
            if op=="diagnostic_report":return {"ok":true,"revision":revision,"report":_build_report()}
            if benchmark_busy:return {"ok":false,"error":"benchmark_busy","revision":revision}
            benchmark_busy=true;_benchmark_cancelled=false;_clear_gesture();_run_diagnostic.call_deferred()
            return {"ok":true,"revision":revision}
        if op=="benchmark":_clear_gesture()
    return super.command(request)
func _clear_gesture() -> void:
    _touches.clear();_mouse_dragging=false;_drag_delta=Vector2.ZERO;_zoom_ratio=1.
func _inside_picture(position: Vector2) -> bool:
    return picture!=null and picture.get_global_rect().has_point(position)
func _input(event: InputEvent) -> void:
    if benchmark_busy or (_report_dialog!=null and _report_dialog.visible):return
    if event is InputEventScreenTouch:
        if event.pressed:
            if not _inside_picture(event.position) or _touches.size()>=2:return
            _touches[event.index]=event.position
        else:
            if not _touches.has(event.index):return
            _touches.erase(event.index)
        get_viewport().set_input_as_handled()
    elif event is InputEventScreenDrag and _touches.has(event.index):
        if _touches.size()==1:_drag_delta+=event.position-Vector2(_touches[event.index])
        else:
            var indices: Array=_touches.keys();var other: int=int(indices[0] if indices[1]==event.index else indices[1])
            var before: float=Vector2(_touches[event.index]).distance_to(_touches[other]);var after: float=event.position.distance_to(_touches[other])
            if before>8. and after>8.:_zoom_ratio*=before/after
        _touches[event.index]=event.position;get_viewport().set_input_as_handled()
    elif event is InputEventMouseButton and event.device!=InputEvent.DEVICE_ID_EMULATION:
        if event.button_index==MOUSE_BUTTON_LEFT:
            if event.pressed and _inside_picture(event.position):_mouse_dragging=true
            elif not event.pressed:_mouse_dragging=false
        if event.pressed and _inside_picture(event.position) and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
            _zoom_ratio*=.9 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.1;get_viewport().set_input_as_handled()
    elif event is InputEventMouseMotion and event.device!=InputEvent.DEVICE_ID_EMULATION and _mouse_dragging:
        _drag_delta+=event.relative;get_viewport().set_input_as_handled()
func _notification(what: int) -> void:
    if what==NOTIFICATION_APPLICATION_FOCUS_OUT:_clear_gesture()
func _flush_gesture() -> void:
    if _drag_delta==Vector2.ZERO and is_equal_approx(_zoom_ratio,1.):return
    var values: Dictionary={}
    if _drag_delta!=Vector2.ZERO:
        values["camera_yaw"]=wrapf(float(state["camera_yaw"])-_drag_delta.x*180./maxf(picture.size.x,1.),-180.,180.)
        values["camera_elevation"]=clampf(float(state["camera_elevation"])+_drag_delta.y*95./maxf(picture.size.y,1.),-10.,85.)
    if not is_equal_approx(_zoom_ratio,1.):values["distance_factor"]=clampf(float(state["distance_factor"])*_zoom_ratio,.6,2.)
    _drag_delta=Vector2.ZERO;_zoom_ratio=1.
    if command({"op":"set_values","values":values})["ok"]:_gesture_changes+=1
func _process(delta: float) -> void:
    if not benchmark_busy:_flush_gesture()
    super._process(delta)
    _frame_rows.append({"interval_ms":delta*1000.,"godot_process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.,"revision":revision})
    if _frame_rows.size()>360:_frame_rows.pop_front()
    _live_clock+=delta
    if _live_clock<1. or effect==null:return
    _live_clock=0.
    if _diagnostic_label!=null:_diagnostic_label.text=Diagnostics.brief(Diagnostics.summarize(effect.pass_profile.snapshot()))
func _build_report() -> Dictionary:
    var profile: Dictionary=effect.pass_profile.snapshot() if effect!=null else {}
    var lighting: Dictionary=transport.transport_metrics() if transport!=null else {}
    var apply_times: Array=[];var process_times: Array=[];var intervals: Array=[]
    for row in _cpu_applies:apply_times.append(row["elapsed_ms"])
    for row in _frame_rows:process_times.append(row["godot_process_ms"]);intervals.append(row["interval_ms"])
    var viewport_rid: RID=get_viewport().get_viewport_rid()
    return {"schema":"lie-mobile-diagnostics/1","app_version":"1.1.0-diagnostics-touch","created_utc":Time.get_datetime_string_from_system(true),"device":OS.get_model_name(),"os":OS.get_name(),"gpu":RenderingServer.get_video_adapter_name(),"physical_android":OS.get_name()=="Android","state":state.duplicate(true),"revision":revision,"display_fps":Engine.get_frames_per_second(),"cpu_control_apply":Diagnostics.percentiles(apply_times),"godot_process":Diagnostics.percentiles(process_times),"display_frame_intervals":Diagnostics.percentiles(intervals),"viewport_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid),"viewport_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid),"appearance_requested_bytes":effect.allocation_bytes if effect!=null else 0,"transport_requested_bytes":transport.allocation_bytes if transport!=null else 0,"godot_static_memory_bytes":OS.get_static_memory_usage(),"gpu_analysis":Diagnostics.summarize(profile),"appearance_passes":profile,"transport":lighting,"cache":effect.cache_metrics() if effect!=null else {},"cpu_apply_rows":_cpu_applies.duplicate(true),"frame_rows":_frame_rows.duplicate(true),"benchmark":_benchmark_report.duplicate(true),"current_mode_diagnostic":_diagnostic_report.duplicate(true),"scope":"Display FPS includes cached images. CPU control time excludes GPU completion. Frame intervals include scheduling/vsync. Viewport timing scope depends on backend. Requested RID bytes are not process PSS or measured VRAM. No GPU image or buffer readbacks."}
func _run_benchmark(quick: bool) -> void:
    var first_serial: int=effect.frame_count+1
    await super._run_benchmark(quick)
    _benchmark_report["gpu_analysis"]=Diagnostics.summarize(_benchmark_report.get("passes",{}),first_serial)
    _persist_report("user://lie-benchmark-last.json",_benchmark_report)
func _diagnostic_trials(backup: Dictionary) -> Array:
    # Explicitly separate camera rebuilds, radiometry and moved-source shadows.
    # Each path is repeated three times at the user's current quality settings.
    var trials: Array=[]
    for repeat in range(3):
        trials.append({"kind":"camera","values":{"camera_yaw":wrapf(float(backup["camera_yaw"])+[5.,-5.,0.][repeat],-180.,180.)}})
    var power: float=float(backup["light_power"])
    var changed_power: float=clampf(power*.9,.25,3.)
    if is_equal_approx(changed_power,power):changed_power=clampf(power*1.1,.25,3.)
    for value in [changed_power,(changed_power+power)*.5,power]:trials.append({"kind":"light_power","values":{"light_power":value}})
    for repeat in range(3):trials.append({"kind":"light_position","values":{"light_azimuth":wrapf(float(backup["light_azimuth"])+[8.,-8.,0.][repeat],-180.,180.)}})
    return trials
func _run_diagnostic() -> void:
    var backup: Dictionary=state.duplicate(true);var events: Array=[];var error: String=""
    var start_serial: int=effect.frame_count;var transport_start: int=transport.frame_count
    var trials: Array=_diagnostic_trials(backup)
    for trial in trials:
        if _benchmark_cancelled:break
        if _benchmark_status!=null:_benchmark_status.text="Midiendo "+trial["kind"]+" · %d/9" % (events.size()+1)
        var before: int=effect.frame_count;var begin: int=Time.get_ticks_usec()
        var outcome: Dictionary=_benchmark_set_values(trial["values"])
        var apply_ms: float=float(Time.get_ticks_usec()-begin)/1000.
        if not outcome["ok"]:error=str(outcome);break
        var waited: int=0
        while effect.frame_count<=before and waited<600 and not _benchmark_cancelled:
            await get_tree().process_frame;waited+=1
        if _benchmark_cancelled:break
        if waited>=600:error="render_timeout";break
        var serial: int=effect.frame_count;var event_ms: float=float(Time.get_ticks_usec()-begin)/1000.
        for i in range(6):await get_tree().process_frame
        events.append({"kind":trial["kind"],"serial":serial,"transport_serial":transport.frame_count,"cpu_command_ms":apply_ms,"submit_event_latency_ms":event_ms})
    # Drain asynchronous timestamp metadata before restoring, never GPU images.
    for i in range(8):await get_tree().process_frame
    var profile: Dictionary=effect.pass_profile.snapshot();var transport_rows: Array=[]
    for row in transport.transport_metrics().get("profile",[]):
        if int(row["serial"])>transport_start:transport_rows.append(row)
    var restore: Dictionary=_benchmark_set_values(backup)
    var event_kinds: Dictionary={}
    for event in events:event_kinds[int(event["serial"])]=event["kind"]
    _diagnostic_report={"events":events,"passes":profile,"gpu_analysis":Diagnostics.summarize(profile,start_serial+1,event_kinds),"transport_rows":transport_rows,"cancelled":_benchmark_cancelled,"error":error,"restored":restore["ok"] and state==backup,"scope":"Current options; three camera, three radiometry and three source-position changes. Event latency ends at CPU render submission, not GPU completion; use asynchronous GPU timestamps for GPU cost."}
    _persist_report("user://lie-current-mode-last.json",_diagnostic_report)
    benchmark_busy=false
    if _benchmark_status!=null:_benchmark_status.text="Medición cancelada" if _benchmark_cancelled else "Error: "+error if error!="" else "Medición lista · abre Informe"
func _persist_report(path: String,report: Dictionary) -> bool:
    var file:=FileAccess.open(path,FileAccess.WRITE)
    if file==null:return false
    file.store_string(JSON.stringify(report,"  ",true,true));file.flush();var valid: bool=file.get_error()==OK;file.close();return valid
func _report_header(report: Dictionary) -> String:
    var text: String="LIE 1.1 · INFORME DE RENDIMIENTO\n%s · %s\nPantalla: %d FPS (incluye caché)\n" % [report["device"],report["gpu"],report["display_fps"]]
    var analysis: Dictionary=report["current_mode_diagnostic"].get("gpu_analysis",report["gpu_analysis"])
    text+=Diagnostics.brief(analysis)+"\n\nLos porcentajes identifican trabajo GPU; CPU, esperas y transporte se informan aparte.\n\n"
    return text
func _show_report() -> void:
    _clear_gesture();var report: Dictionary=_build_report();var saved: bool=_persist_report("user://lie-performance-last.json",report)
    # Android clipboard transfers have a finite IPC budget. Do not duplicate
    # hundreds of raw rows from all three retained reports in that transfer.
    # Full raw evidence stays in the saved JSON; copied text keeps reductions,
    # device/options, trial serials and the latest timestamp rows.
    var portable: Dictionary=report.duplicate(true)
    portable.erase("cpu_apply_rows");portable.erase("frame_rows")
    portable["appearance_passes"]["rows"]=portable["appearance_passes"].get("rows",[]).slice(-32)
    for key in ["benchmark","current_mode_diagnostic"]:
        if portable[key].has("passes"):portable[key].erase("passes")
    portable["copy_scope"]="Compact report; full timestamp/frame history saved in lie-performance-last.json"
    _report_content=_report_header(report)+JSON.stringify(portable,"",true,true)
    if _report_content.to_utf8_buffer().size()>196608:
        portable["appearance_passes"].erase("rows")
        _report_content=_report_header(report)+JSON.stringify(portable,"",true,true)
    _report_text.text=_report_content;_report_text.scroll_vertical=0
    _report_feedback.text="Informe guardado. Pulsa Copiar y pega en el chat." if saved else "No se pudo guardar. El informe sigue disponible aquí para seleccionarlo."
    _report_dialog.show();_report_text.grab_focus()
func _copy_report() -> void:
    if _copy_busy or _report_content.is_empty():return
    _copy_busy=true;DisplayServer.clipboard_set(_report_content)
    await get_tree().create_timer(.2).timeout
    if DisplayServer.clipboard_get()==_report_content:_report_feedback.text="Informe copiado. Ya puedes pegarlo en el chat."
    else:
        _report_text.grab_focus();_report_text.select_all()
        _report_feedback.text="No se pudo confirmar la copia. Texto seleccionado: mantén pulsado y elige Copiar."
    _copy_busy=false
func _ui() -> void:
    super._ui();var box: Node=status.get_parent()
    # Replace the silent legacy clipboard callback with an inspectable report.
    for child in box.get_children():
        if child is Button and child.text=="Copiar resultado":box.remove_child(child);child.queue_free()
    var ui: CanvasLayer=picture.get_parent()
    for item in ui.get_children():
        if item is Label and item.text.begins_with("LIE ·"):item.text="LIE · Diagnóstico · 1.1.0"
    var hint: Label=_label(ui,"Un dedo: girar la vista · Dos dedos: acercar o alejar",16);hint.position=Vector2(32,750);hint.mouse_filter=Control.MOUSE_FILTER_IGNORE
    var report_button:=Button.new();report_button.text="Informe";report_button.position=Vector2(598,12);report_button.size=Vector2(130,40);report_button.pressed.connect(_show_report);ui.add_child(report_button)
    var measure:=Button.new();measure.text="Medir modo actual";measure.position=Vector2(740,12);measure.size=Vector2(190,40);measure.pressed.connect(func():command({"op":"diagnose"}));ui.add_child(measure)
    _diagnostic_label=_label(box,"Mueve la vista para medir etapas GPU.",16);_diagnostic_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_diagnostic_label.custom_minimum_size.x=270
    var show:=Button.new();show.text="Ver y copiar informe";show.pressed.connect(_show_report);box.add_child(show)
    _report_dialog=PanelContainer.new();_report_dialog.position=Vector2(90,55);_report_dialog.size=Vector2(1100,690);_report_dialog.z_index=20;ui.add_child(_report_dialog)
    var style:=StyleBoxFlat.new();style.bg_color=Color(.025,.035,.05,1.);_report_dialog.add_theme_stylebox_override("panel",style)
    var report_box:=VBoxContainer.new();_report_dialog.add_child(report_box)
    _report_feedback=_label(report_box,"",18);_report_feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    _report_text=TextEdit.new();_report_text.editable=false;_report_text.size_flags_vertical=Control.SIZE_EXPAND_FILL;_report_text.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;report_box.add_child(_report_text)
    var buttons:=HBoxContainer.new();report_box.add_child(buttons)
    for action in [["Copiar informe",_copy_report],["Seleccionar todo",func():_report_text.grab_focus();_report_text.select_all()],["Cerrar",func():_report_dialog.hide()]]:
        var button:=Button.new();button.text=action[0];button.custom_minimum_size=Vector2(180,45);button.pressed.connect(action[1]);buttons.add_child(button)
    _report_dialog.hide()
func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot()
    result["control_contract"]["diagnostics"]={"start":{"op":"diagnose"},"report":{"op":"diagnostic_report"},"cancel":{"op":"benchmark_cancel"},"restores_state":true}
    result["touch_controls"]={"one_finger":"camera orbit","two_fingers":"camera distance","gesture_transactions":_gesture_changes,"changes_wall_geometry":false}
    return result
