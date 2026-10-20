extends "res://lie_wall24_android_lab.gd"
const DirectEffect = preload("res://lie_direct_effect.gd")
const DIRECT_MODES = {"regions_1080":{"internal_resolution":1080,"direct_backend":"regions"},"views_1080":{"internal_resolution":1080,"direct_backend":"views"},"views_fast_1080":{"internal_resolution":1080,"direct_backend":"views_fast"},"regions_720":{"internal_resolution":720,"direct_backend":"regions"},"views_720":{"internal_resolution":720,"direct_backend":"views"},"views_fast_720":{"internal_resolution":720,"direct_backend":"views_fast"}}
var _direct_status_clock: float = 0.
const DIRECT_LABELS = {"regions_1080":"Regiones 1080","views_1080":"Vistas ajustadas 1080","views_fast_1080":"Vistas simples 1080","regions_720":"Regiones 720","views_720":"Vistas ajustadas 720","views_fast_720":"Vistas simples 720"}

func _ready() -> void:
    state["direct_backend"] = "views"
    super._ready()

func _coded_effect_factory() -> CompositorEffect: return DirectEffect.new(720)

func _apply() -> void:
    if effect != null: effect.set_direct_backend(str(state.get("direct_backend","surface")))
    super._apply()

func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("values",{}) is Dictionary:
        var values: Dictionary = request.get("values",{})
        if values.has("direct_backend") and values["direct_backend"] not in ["reference","regions","views","views_fast"]:
            return {"ok":false,"error":"direct_backend","revision":revision}
    return super.command(request)

func _benchmark_set_values(values: Dictionary) -> Dictionary:
    if values.has("direct_backend") and values["direct_backend"] not in ["reference","regions","views","views_fast"]: return {"ok":false,"error":"direct_backend","revision":revision}
    return super._benchmark_set_values(values)

func _stream_event(values: Dictionary, kind: String, mode: String, cycle: int, force: bool = false) -> Dictionary:
    var event: Dictionary = await super._stream_event(values,kind,mode,cycle,force)
    event["direct_backend"] = effect.effective_direct_backend
    event["direct_work"] = effect.cache_metrics()["direct_surface"]
    if effect.effective_direct_backend == "reference_fallback": event["error"] = effect.direct_failure
    return event

func _access_collect_stages(events: Array, rows: Array, seen: Dictionary) -> void:
    var selected: Dictionary = {}
    for event in events:
        if event.has("serial"): selected[int(event["serial"])] = true
    for row in effect.native_stages.snapshot().get("rows",[]):
        var key: String = str(row["serial"])+"|"+row["pass"]
        if selected.has(int(row["serial"])) and row["pass"] in ["primary","shadow_maps","node_response","shading","output"] and not seen.has(key):
            rows.append(row); seen[key] = true

func _access_stage_summary(events: Array, rows: Array, whole: Array) -> Array:
    var groups: Dictionary = {}; var selected: Dictionary = {}; var costs: Dictionary = {}; var totals: Dictionary = {}
    for event in events:
        if not event.has("serial"): continue
        var key: String = event["mode"]+"|"+event["kind"]
        if not groups.has(key): groups[key] = {"mode":event["mode"],"kind":event["kind"],"passes":{},"whole":[],"residual":[]}
        selected[int(event["serial"])] = key
    for row in rows:
        var serial: int = int(row["serial"])
        if not selected.has(serial): continue
        var group: Dictionary = groups[selected[serial]]; var name: String = row["pass"]
        if not group["passes"].has(name): group["passes"][name] = []
        group["passes"][name].append(float(row["gpu_ns"])/1000000.)
        costs[serial] = costs.get(serial,0.)+float(row["gpu_ns"])/1000000.
    for row in whole:
        var serial: int = int(row["serial"])
        if selected.has(serial) and row["pass"]=="solve": totals[serial] = float(row["gpu_ns"])/1000000.
    for serial in totals:
        var group: Dictionary = groups[selected[serial]]
        group["whole"].append(totals[serial]); group["residual"].append(totals[serial]-costs.get(serial,0.))
    var result: Array = []
    for group in groups.values():
        var passes: Dictionary = {}
        for name in group["passes"]: passes[name] = Diagnostics.percentiles(group["passes"][name])
        result.append({"mode":group["mode"],"kind":group["kind"],"passes":passes,"whole_instrumented_gpu":Diagnostics.percentiles(group["whole"]),"unattributed_gpu":Diagnostics.percentiles(group["residual"])})
    return result

func _access_whole_summary(rows: Array, events: Array) -> Array:
    var valid: Array = []
    for event in events:
        if event.has("serial"): valid.append(event)
    return _stream_summary(rows,valid)

func _run_comparison(quick: bool) -> void:
    hardware.release_counters(); hardware_profile = {}
    var backup: Dictionary = state.duplicate(true); var events: Array = []; var warmup: Array = []; var all_events: Array = []
    var rows: Array = []; var seen: Dictionary = {}; var error: String = ""
    var rounds: int = 1 if quick else 4; var modes: Array = DIRECT_MODES.keys()
    var stage_events: Array = []; var stage_warmup: Array = []; var stage_all: Array = []
    var stage_rows: Array = []; var stage_seen: Dictionary = {}; var stage_whole: Array = []; var stage_whole_seen: Dictionary = {}
    # Whole solves have only outer timestamps. A separate rotated diagnostic
    # repeats the same work with stage marks; its timing is never mixed in.
    for phase in range(2):
        var cycles: int = rounds if phase==0 else 1
        for cycle in range(cycles):
            for offset in range(modes.size()):
                if _benchmark_cancelled or error!="": break
                var mode: String = modes[(cycle+offset+phase*2)%modes.size()]
                var reset: Dictionary = backup.duplicate(true); reset.merge(DIRECT_MODES[mode],true)
                reset.merge({"raster_backend":"compute","area_lights":false,"quality_2x":false,"tight_bounds":true,"screen_tiles":false,"compact_shadows":false,"visibility_stream":false,"visibility_diagnostics":false,"kernel_mode":"split","power_response":true,"stage_timestamps":phase==1,"lean_barriers":false},true)
                var target_events: Array = events if phase==0 else stage_events
                var target_warmup: Array = warmup if phase==0 else stage_warmup
                var target_all: Array = all_events if phase==0 else stage_all
                var event: Dictionary = await _stream_event(reset,"initial_geometry",mode,cycle,true)
                target_warmup.append(event); target_all.append(event)
                if event.has("error"): error = event["error"]; break
                for trial in _diagnostic_trials(reset):
                    if _benchmark_cancelled: break
                    event = await _stream_event(trial["values"],trial["kind"],mode,cycle)
                    target_warmup.append(event); target_all.append(event)
                    if event.has("error"): error = event["error"]; break
                if error!="": break
                for trial in _diagnostic_trials(reset):
                    if _benchmark_cancelled: break
                    if _benchmark_status!=null: _benchmark_status.text = "%s %s · %d" % ["Etapas" if phase==1 else "Midiendo",DIRECT_LABELS[mode],target_events.size()+1]
                    event = await _stream_event(trial["values"],trial["kind"],mode,cycle)
                    target_events.append(event); target_all.append(event)
                    if event.has("error"): error = event["error"]; break
                if phase==0: _comparison_collect(all_events,rows,seen)
                else:
                    _comparison_collect(stage_all,stage_whole,stage_whole_seen)
                    _access_collect_stages(stage_all,stage_rows,stage_seen)
            if _benchmark_cancelled or error!="": break
        if _benchmark_cancelled or error!="": break
    for i in range(8): await get_tree().process_frame
    _comparison_collect(all_events,rows,seen); _comparison_collect(stage_all,stage_whole,stage_whole_seen); _access_collect_stages(stage_all,stage_rows,stage_seen)
    var restore: Dictionary = _benchmark_set_values(backup)
    _comparison_report = {"schema":"lie-captured-views-comparison/1","scene":backup,"rounds":rounds,"modes":DIRECT_MODES,"events":events,"warmup_events":warmup,"warmup_summary":_access_whole_summary(rows,warmup),"summary":_access_whole_summary(rows,events),"passes":{"rows":rows},"stage_events":stage_events,"stage_warmup_events":stage_warmup,"stage_summary":_access_stage_summary(stage_events,stage_rows,stage_whole),"stages":{"rows":stage_rows,"whole_rows":stage_whole},"expected_stage_events":modes.size()*9,"expected_events":rounds*modes.size()*9,"requested_events":rounds*modes.size()*9,"cancelled":_benchmark_cancelled,"error":error,"restored":restore["ok"] and state==backup,"scope":"Three executable representations at 1080 and 720 with the same 720 output, full-resolution original material atlas, transport and lighting. Regions is the accepted 2.4 baseline; views are offline visibility captures with three fixed angular candidates, three depth projections and two source refinements. Both use identical regions shadow maps. Simple views use one reference-depth sample without refinement as a precision/cost control. Both captured modes are approximate; no timed readbacks or hidden fallback. Main whole intervals have no inner stage marks. Stages are a separate diagnostic with independently retained whole intervals. Do not add stage medians to whole time. Bank/atlas uploads and shared transport separately scoped; cold blocks and warm-up retained."}
    _persist_report("user://lie-captured-views-last.json",_comparison_report); benchmark_busy = false
    if _benchmark_status!=null: _benchmark_status.text = "Comparación terminada · pulsa Informe" if error=="" else "Comparación incompleta: "+error

func _build_report() -> Dictionary:
    var result: Dictionary = super._build_report(); result["app_version"] = "2.5.0-captured-views"
    result["reference_resident_requested_bytes"] = effect.allocation_bytes
    result["appearance_requested_bytes"] += result["cache"]["direct_surface"]["additional_requested_bytes"]
    return result

func _portable_report(report: Dictionary) -> Dictionary:
    var result: Dictionary = super._portable_report(report.duplicate(true))
    result["cache"]["direct_surface"] = report["cache"]["direct_surface"]
    if result.has("kernel_comparison"):
        var compact: Dictionary = report["kernel_comparison"].duplicate(true)
        for key in ["events","warmup_events","passes","stage_events","stage_warmup_events","stages"]: compact.erase(key)
        compact["recorded_events"] = report["kernel_comparison"]["events"].size()
        compact["warmup_recorded_events"] = report["kernel_comparison"]["warmup_events"].size()
        compact["recorded_stage_events"] = report["kernel_comparison"]["stage_events"].size()
        compact["stage_warmup_recorded_events"] = report["kernel_comparison"]["stage_warmup_events"].size()
        result["kernel_comparison"] = compact
    result["copy_scope"] = "Three representations at both resolutions with identical shadow backend. Full events in lie-captured-views-last.json; main whole intervals and instrumented stage diagnostic are separate."
    return result

func _report_header(report: Dictionary) -> String:
    var text: String = "LIE 2.5 · VISTAS CAPTURADAS\n%s · %s\n" % [report["device"],report["gpu"]]
    var comparison: Dictionary = report.get("kernel_comparison",{})
    for kind in ["camera","light_power","light_position"]:
        text += "\n"+{"camera":"Cámara","light_power":"Potencia","light_position":"Posición de luz"}[kind]
        for mode in DIRECT_MODES:
            for group in comparison.get("summary",[]):
                if group["kind"]==kind and group["mode"]==mode: text += "\n%s: %.2f ms · p95 %.2f · %d eventos" % [DIRECT_LABELS[mode],group["gpu"]["p50_ms"],group["gpu"]["p95_ms"],group["gpu"]["samples"]]
    text += "\n\nEtapas p50 · diagnóstico separado (ms)"
    for group in comparison.get("stage_summary",[]):
        text += "\n%s · %s" % [DIRECT_LABELS[group["mode"]],group["kind"]]
        for name in ["primary","shadow_maps","node_response","shading","output"]:
            if group["passes"].has(name): text += " · %s %.2f" % [name,group["passes"][name]["p50_ms"]]
    return text+"\n\nVistas experimentales: visibilidad precapturada y consultas limitadas; pueden cambiar bordes, profundidad y movimiento. Sombras comunes de regiones. Etapas separadas del intervalo principal.\n\n"

func _ui() -> void:
    super._ui()
    var box: Node = status.get_parent(); _label(box,"VISTAS CAPTURADAS",19)
    _label(box,"Vistas: aproximación de profundidad; compara bordes y movimiento",15)
    var select := OptionButton.new()
    for entry in [["Vistas ajustadas experimental","views"],["Vistas simples sin ajuste","views_fast"],["Regiones (2.4)","regions"],["Referencia discos","reference"]]:
        select.add_item(entry[0]); select.set_item_metadata(select.item_count-1,entry[1])
    select.item_selected.connect(func(index: int): command({"op":"set_values","values":{"direct_backend":select.get_item_metadata(index)}}))
    box.add_child(select); controls["direct_backend"] = select
    # Fixed native lighting model exposes its common scene controls. Old
    # per-source implementation switches remain available in reference mode.
    var visible_controls: Array = ["camera_yaw","camera_elevation","distance_factor","light_azimuth","light_power","exposure","shadows","lighting_preset","clay_absorption","fill_azimuth","fill_power","key_enabled","fill_enabled","material_response","internal_resolution","direct_backend"]
    for key in controls:
        if key not in visible_controls: controls[key].hide()
    if _kernel_picker != null: _kernel_picker.hide()
    for item in box.get_children():
        if item is Button and item.text=="Medir solo el modo actual": item.hide()
    for item in picture.get_parent().get_children():
        if item is Label and item.text.begins_with("LIE ·"): item.text = "LIE · Vistas capturadas · 2.5"

func agent_snapshot() -> Dictionary:
    var result: Dictionary = super.agent_snapshot()
    result["control_contract"]["direct_backends"] = ["reference","regions","views","views_fast"]
    result["control_contract"]["comparison_modes"] = DIRECT_MODES
    return result

func _process(delta: float) -> void:
    super._process(delta)
    _direct_status_clock += delta
    if _direct_status_clock < 1. or effect == null: return
    _direct_status_clock = 0.
    if _diagnostic_label != null: _diagnostic_label.text = Diagnostics.brief(Diagnostics.summarize(effect.solve_profile.snapshot()))
    if status != null and effect.effective_direct_backend in ["regions","views","views_fast"]:
        status.text = "%s · experimental\nInterior: %d × %d · salida: %d × %d\nImágenes actualizadas: %d" % [{"regions":"Regiones","views":"Vistas ajustadas","views_fast":"Vistas simples"}.get(effect.effective_direct_backend,effect.effective_direct_backend),effect.render_size,effect.render_size,effect.output_size,effect.output_size,effect.frame_count]
    if status != null and effect.direct_failure != "": status.text += "\nSuperficie no disponible: " + effect.direct_failure

func _refresh() -> void:
    super._refresh()
    if controls.has("direct_backend"):
        var select: OptionButton = controls["direct_backend"]
        for i in range(select.item_count):
            if select.get_item_metadata(i)==state["direct_backend"]: select.select(i)
