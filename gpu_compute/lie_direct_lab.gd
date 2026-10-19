extends "res://lie_wall24_android_lab.gd"
const DirectEffect = preload("res://lie_direct_effect.gd")
const DIRECT_MODES = {"reference_1080":{"internal_resolution":1080,"direct_backend":"reference"},"surface_1080":{"internal_resolution":1080,"direct_backend":"surface"},"surface_720":{"internal_resolution":720,"direct_backend":"surface"}}
var _direct_status_clock: float = 0.
const DIRECT_LABELS = {"reference_1080":"Referencia 1080","surface_1080":"Superficie 1080","surface_720":"Superficie 720"}

func _ready() -> void:
    state["direct_backend"] = "surface"
    super._ready()

func _coded_effect_factory() -> CompositorEffect: return DirectEffect.new(720)

func _apply() -> void:
    if effect != null: effect.set_direct_backend(str(state.get("direct_backend","surface")))
    super._apply()

func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("values",{}) is Dictionary:
        var values: Dictionary = request.get("values",{})
        if values.has("direct_backend") and values["direct_backend"] not in ["reference","surface"]:
            return {"ok":false,"error":"direct_backend","revision":revision}
    return super.command(request)

func _benchmark_set_values(values: Dictionary) -> Dictionary:
    if values.has("direct_backend") and values["direct_backend"] not in ["reference","surface"]: return {"ok":false,"error":"direct_backend","revision":revision}
    return super._benchmark_set_values(values)

func _stream_event(values: Dictionary, kind: String, mode: String, cycle: int, force: bool = false) -> Dictionary:
    var event: Dictionary = await super._stream_event(values,kind,mode,cycle,force)
    event["direct_backend"] = effect.effective_direct_backend
    event["direct_work"] = effect.cache_metrics()["direct_surface"]
    if effect.effective_direct_backend == "reference_fallback": event["error"] = effect.direct_failure
    return event

func _run_comparison(quick: bool) -> void:
    hardware.release_counters(); hardware_profile = {}
    var backup: Dictionary = state.duplicate(true); var events: Array = []; var warmup: Array = []; var all_events: Array = []
    var rows: Array = []; var seen: Dictionary = {}; var error: String = ""
    var rounds: int = 1 if quick else 4; var modes: Array = DIRECT_MODES.keys()
    for cycle in range(rounds):
        for offset in range(modes.size()):
            if _benchmark_cancelled or error != "": break
            var mode: String = modes[(cycle+offset)%modes.size()]
            var reset: Dictionary = backup.duplicate(true); reset.merge(DIRECT_MODES[mode],true)
            reset.merge({"raster_backend":"compute","area_lights":false,"quality_2x":false,"tight_bounds":true,"screen_tiles":false,"compact_shadows":false,"visibility_stream":false,"visibility_diagnostics":false,"kernel_mode":"split","power_response":true,"stage_timestamps":false,"lean_barriers":false},true)
            var event: Dictionary = await _stream_event(reset,"initial_geometry",mode,cycle,true)
            warmup.append(event); all_events.append(event)
            if event.has("error"): error = event["error"]; break
            for trial in _diagnostic_trials(reset):
                if _benchmark_cancelled: break
                event = await _stream_event(trial["values"],trial["kind"],mode,cycle)
                warmup.append(event); all_events.append(event)
                if event.has("error"): error = event["error"]; break
            if error != "": break
            for trial in _diagnostic_trials(reset):
                if _benchmark_cancelled: break
                if _benchmark_status != null: _benchmark_status.text = "Midiendo %s · %d" % [DIRECT_LABELS[mode],events.size()+1]
                event = await _stream_event(trial["values"],trial["kind"],mode,cycle)
                events.append(event); all_events.append(event)
                if event.has("error"): error = event["error"]; break
            _comparison_collect(all_events,rows,seen)
    for i in range(8): await get_tree().process_frame
    _comparison_collect(all_events,rows,seen)
    var restore: Dictionary = _benchmark_set_values(backup)
    _comparison_report = {"schema":"lie-direct-surface-comparison/1","scene":backup,"rounds":rounds,"modes":DIRECT_MODES,"events":events,"warmup_events":warmup,"warmup_summary":_stream_summary(rows,warmup),"summary":_stream_summary(rows,events),"passes":{"rows":rows},"expected_events":rounds*27,"requested_events":rounds*27,"cancelled":_benchmark_cancelled,"error":error,"restored":restore["ok"] and state==backup,"scope":"Actual different opaque representation, same 720 output. Reference1080/Surface1080 share internal resolution; Surface720 is separately labelled. Whole appearance includes primary/changed shadow map builds and unified shading. Static attributed field is compiled offline and uploaded before blocks. All cold block and warmup samples retained. Fine shadows and finite-resolution coverage differ; software Vulkan is not Mali FPS."}
    _persist_report("user://lie-direct-surface-last.json",_comparison_report); benchmark_busy = false
    if _benchmark_status != null: _benchmark_status.text = "Comparación terminada · pulsa Informe" if error=="" else "Comparación incompleta: "+error

func _build_report() -> Dictionary:
    var result: Dictionary = super._build_report(); result["app_version"] = "2.3.0-direct-surface"
    result["reference_resident_requested_bytes"] = effect.allocation_bytes
    result["appearance_requested_bytes"] += result["cache"]["direct_surface"]["additional_requested_bytes"]
    return result

func _portable_report(report: Dictionary) -> Dictionary:
    var result: Dictionary = super._portable_report(report.duplicate(true))
    result["cache"]["direct_surface"] = report["cache"]["direct_surface"]
    if result.has("kernel_comparison"):
        var compact: Dictionary = report["kernel_comparison"].duplicate(true)
        for key in ["events","warmup_events","passes"]: compact.erase(key)
        compact["recorded_events"] = report["kernel_comparison"]["events"].size()
        compact["warmup_recorded_events"] = report["kernel_comparison"]["warmup_events"].size()
        result["kernel_comparison"] = compact
    result["copy_scope"] = "Different compiled surface representation. Full events and warmup in lie-direct-surface-last.json; identical-resolution pair explicitly labelled."
    return result

func _report_header(report: Dictionary) -> String:
    var text: String = "LIE 2.3 · SUPERFICIE DIRECTA\n%s · %s\n" % [report["device"],report["gpu"]]
    var comparison: Dictionary = report.get("kernel_comparison",{})
    for kind in ["camera","light_power","light_position"]:
        text += "\n"+{"camera":"Cámara","light_power":"Potencia","light_position":"Posición de luz"}[kind]
        for mode in DIRECT_MODES:
            for group in comparison.get("summary",[]):
                if group["kind"]==kind and group["mode"]==mode: text += "\n%s: %.2f ms · p95 %.2f · %d eventos" % [DIRECT_LABELS[mode],group["gpu"]["p50_ms"],group["gpu"]["p95_ms"],group["gpu"]["samples"]]
    return text+"\n\nRepresentación experimental. Comparar imagen y movimiento; sombras y cobertura pueden diferir.\n\n"

func _ui() -> void:
    super._ui()
    var box: Node = status.get_parent(); _label(box,"SUPERFICIE DIRECTA",19)
    _label(box,"Experimental · capas de captura y sombras desde la luz",15)
    var select := OptionButton.new()
    for entry in [["Superficie nueva","surface"],["Referencia","reference"]]:
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
        if item is Label and item.text.begins_with("LIE ·"): item.text = "LIE · Superficie directa · 2.3"

func agent_snapshot() -> Dictionary:
    var result: Dictionary = super.agent_snapshot()
    result["control_contract"]["direct_backends"] = ["reference","surface"]
    result["control_contract"]["comparison_modes"] = DIRECT_MODES
    return result

func _process(delta: float) -> void:
    super._process(delta)
    _direct_status_clock += delta
    if _direct_status_clock < 1. or effect == null: return
    _direct_status_clock = 0.
    if _diagnostic_label != null: _diagnostic_label.text = Diagnostics.brief(Diagnostics.summarize(effect.solve_profile.snapshot()))
    if status != null and effect.effective_direct_backend == "surface":
        status.text = "Superficie nueva · experimental\nInterior: %d × %d · salida: %d × %d\nImágenes actualizadas: %d" % [effect.render_size,effect.render_size,effect.output_size,effect.output_size,effect.frame_count]
    if status != null and effect.direct_failure != "": status.text += "\nSuperficie no disponible: " + effect.direct_failure

func _refresh() -> void:
    super._refresh()
    if controls.has("direct_backend"):
        var select: OptionButton = controls["direct_backend"]
        for i in range(select.item_count):
            if select.get_item_metadata(i)==state["direct_backend"]: select.select(i)
