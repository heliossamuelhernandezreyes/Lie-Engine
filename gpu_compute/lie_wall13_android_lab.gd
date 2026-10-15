extends "res://lie_wall12_android_lab.gd"
const AreaEffect=preload("res://lie_wall13_area_effect.gd")
const AreaTransport=preload("res://lie_wall13_area_transport.gd")
const AreaWorld=preload("res://lie_area_light_world.gd")
const RectEmitter=preload("res://lie_rect_emitter_3d.gd")
var _physical_signature:=PackedByteArray()
var benchmark_busy: bool=false
var _benchmark_cancelled: bool=false
var _benchmark_report: Dictionary={}
var _benchmark_status: Label
func _ready() -> void:
    state["fused_shading"]=true;state["surface_filter"]=true;state["area_lights"]=false;state["area_size"]=.30
    super._ready()
func _coded_effect_factory() -> CompositorEffect:return AreaEffect.new(720)
func _transport_factory() -> CompositorEffect:return AreaTransport.new()
func _light_world_factory() -> Node3D:return AreaWorld.new()
func _point_emitter_factory() -> Node3D:return RectEmitter.new()
func _accept_light_snapshot(snapshot: Dictionary) -> void:
    if transport==null or light_model.is_empty() or snapshot.is_empty():return
    # The inherited scene controls operate on the two logical sources. Only
    # their immutable render snapshot expands to eight physical channels.
    light_model["lights"]=snapshot.get("logical_lights",snapshot["lights"])
    var physical: Dictionary=light_model.duplicate(true);physical["lights"]=snapshot["lights"]
    physical["emission_descriptors"]=snapshot["emission_descriptors"]
    var signature: PackedByteArray=LightRegistry.Model.light_bytes(physical);signature.append_array(snapshot["emission_descriptors"])
    if signature==_physical_signature and transport.desired_light_count==physical["lights"].size():return
    _physical_signature=signature
    if not transport.gpu_ready or transport.desired_light_count!=physical["lights"].size():transport.configure(physical)
    else:transport.set_light_codes(physical)
    if effect!=null:effect.invalidate_lighting()
func _apply() -> void:
    if effect!=null:effect.set_pipeline_options(bool(state["fused_shading"]),bool(state["surface_filter"]))
    for emitter in [key_emitter,fill_emitter]:
        if emitter!=null:emitter.area_enabled=bool(state["area_lights"]);emitter.size_m=Vector2(float(state["area_size"]),float(state["area_size"])*.75)
    super._apply()
    if light_world!=null and effect!=null:
        var c: Array=effect.catalog["masters"]["real_scan_wall"]["bounds_center"]
        var target: Vector3=light_world.global_transform*Vector3(c[0],c[1],c[2])
        for emitter in [key_emitter,fill_emitter]:
            if emitter.global_position.distance_squared_to(target)>.00001:emitter.look_at(target,Vector3.UP)
        light_world.refresh();_accept_light_snapshot(light_world.render_snapshot())
func command(request: Variant) -> Dictionary:
    if request is Dictionary:
        var op: String=str(request.get("op",""))
        if op=="benchmark_result":
            if request.size()!=1:return {"ok":false,"error":"benchmark_fields","revision":revision}
            return {"ok":true,"busy":benchmark_busy,"result":_benchmark_report.duplicate(true),"revision":revision}
        if op=="benchmark_cancel":
            if request.size()!=1:return {"ok":false,"error":"benchmark_fields","revision":revision}
            _benchmark_cancelled=true;return {"ok":true,"revision":revision}
        if op=="benchmark":
            for key in request:
                if key not in ["op","quick"]:return {"ok":false,"error":"benchmark_fields","revision":revision}
            if request.has("quick") and not request["quick"] is bool:return {"ok":false,"error":"quick_type","revision":revision}
            if benchmark_busy:return {"ok":false,"error":"benchmark_busy","revision":revision}
            benchmark_busy=true;_benchmark_cancelled=false;_run_benchmark.call_deferred(bool(request.get("quick",false)))
            return {"ok":true,"revision":revision}
        if benchmark_busy and op!="sample_address":return {"ok":false,"error":"benchmark_busy","revision":revision}
        if request.get("values",{}) is Dictionary:
            var values: Dictionary=request.get("values",{})
            for key in ["fused_shading","surface_filter","area_lights"]:
                if values.has(key) and not values[key] is bool:return {"ok":false,"error":key+"_type","revision":revision}
            if values.has("area_size"):
                var value: Variant=values["area_size"]
                if not (value is int or value is float):return {"ok":false,"error":"area_size_type","revision":revision}
                if not is_finite(float(value)) or value<.01 or value>1.:return {"ok":false,"error":"area_size_range","revision":revision}
    return super.command(request)
func _run_benchmark(quick: bool) -> void:
    var backup: Dictionary=state.duplicate(true);var events: Array=[];var error: String=""
    var modes: Array=[{"name":"point_separate_raw","fused_shading":false,"surface_filter":false,"area_lights":false},{"name":"point_fused_raw","fused_shading":true,"surface_filter":false,"area_lights":false},{"name":"point_fused_filtered","fused_shading":true,"surface_filter":true,"area_lights":false},{"name":"area_fused_filtered","fused_shading":true,"surface_filter":true,"area_lights":true}]
    var angles: Array=[12.,60.] if quick else [12.,35.,60.,80.,60.,35.,12.]
    for mode in modes:
        for angle in angles:
            if _benchmark_cancelled or error!="":break
            if _benchmark_status!=null:_benchmark_status.text="Midiendo "+mode["name"]+" · "+str(angle)+"°"
            var values: Dictionary=mode.duplicate();values.erase("name");values["camera_yaw"]=angle;values["visibility_diagnostics"]=false
            var outcome: Dictionary=super.command({"op":"set_values","values":values})
            if not outcome["ok"]:error=str(outcome);break
            var before: int=effect.frame_count;var begin: int=Time.get_ticks_usec();effect.force_geometry_rebuild()
            var waited: int=0
            while effect.frame_count==before and waited<240 and not _benchmark_cancelled:
                await get_tree().process_frame;waited+=1
            if waited>=240:error="render_timeout";break
            var latency: float=float(Time.get_ticks_usec()-begin)/1000.
            for i in range(4):await get_tree().process_frame
            events.append({"mode":mode["name"],"yaw":angle,"serial":effect.frame_count,"event_latency_ms":latency,"display_fps":Engine.get_frames_per_second(),"internal_size":effect.render_size,"source_uploads":effect.asset_uploads})
        if _benchmark_cancelled or error!="":break
    var restore: Dictionary=super.command({"op":"set_values","values":backup})
    _benchmark_report={"schema":"lie-mobile-benchmark/1","device":OS.get_model_name(),"gpu":RenderingServer.get_video_adapter_name(),"physical_android":OS.get_name()=="Android","events":events,"passes":effect.pass_profile.snapshot(),"cancelled":_benchmark_cancelled,"error":error,"restored":restore["ok"] and state==backup,"scope":"event latency includes CPU/vsync; display FPS includes cached frames; GPU timestamps measure changed-image passes; no GPU image readbacks"}
    var file:=FileAccess.open("user://lie-benchmark-last.json",FileAccess.WRITE)
    if file!=null:file.store_string(JSON.stringify(_benchmark_report,"  ",true,true));file.close()
    benchmark_busy=false
    if _benchmark_status!=null:_benchmark_status.text="Prueba cancelada" if _benchmark_cancelled else "Error: "+error if error!="" else "Prueba terminada · puedes copiar el resultado"
func _ui() -> void:
    super._ui();var box: Node=status.get_parent()
    _label(box,"CONTINUIDAD Y LUZ DE ÁREA",19)
    _check(box,"fused_shading","Fusionar iluminación y composición")
    _check(box,"surface_filter","Estabilizar el material por superficie")
    _check(box,"area_lights","Emisores rectangulares (más coste)")
    _field_slider(box,"area_size","Ancho del emisor (metros)",.01,1.)
    _label(box,"PRUEBA EN ESTE TELÉFONO",19)
    for item in [["Medir cuatro modos","benchmark"],["Cancelar prueba","benchmark_cancel"]]:
        var button:=Button.new();button.text=item[0];var op: String=item[1];button.pressed.connect(func():command({"op":op}));box.add_child(button)
    var copy:=Button.new();copy.text="Copiar resultado";copy.pressed.connect(func():DisplayServer.clipboard_set(JSON.stringify(_benchmark_report,"  ",true,true)));box.add_child(copy)
    _benchmark_status=Label.new();_benchmark_status.text="La prueba restaura tus ajustes al terminar";_benchmark_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(_benchmark_status)
    for layer in get_children():
        if layer is CanvasLayer:
            for item in layer.get_children():
                if item is Label and item.text.begins_with("LIE ·"):item.text="LIE · Continuidad y luz de área · 1.0.0"
func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot()
    for key in ["fused_shading","surface_filter","area_lights"]:
        if not result["control_contract"]["booleans"].has(key):result["control_contract"]["booleans"].append(key)
    result["control_contract"]["limits"]["area_size"]=[.01,1.]
    result["control_contract"]["benchmark"]={"start":{"op":"benchmark","quick":false},"result":{"op":"benchmark_result"},"cancel":{"op":"benchmark_cancel"},"restores_state":true}
    if light_world!=null:
        var snapshot: Dictionary=light_world.render_snapshot();snapshot.erase("emission_descriptors");result["area_lights"]=snapshot
    return result
