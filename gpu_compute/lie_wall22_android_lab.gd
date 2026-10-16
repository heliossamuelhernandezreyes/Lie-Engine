extends "res://lie_wall21_android_lab.gd"
const TileEffect=preload("res://lie_wall22_tile_effect.gd")
const TILE_MODES={"reference":{"screen_tiles":false,"tight_bounds":false},"tiles":{"screen_tiles":true,"tight_bounds":false},"tight":{"screen_tiles":false,"tight_bounds":true},"combined":{"screen_tiles":true,"tight_bounds":true}}
const TILE_LABELS={"reference":"Referencia","tiles":"Bloques","tight":"Límites","combined":"Ambos"}
func _ready() -> void:
    state["screen_tiles"]=false;super._ready()
func _coded_effect_factory() -> CompositorEffect:return TileEffect.new(720)
func _apply() -> void:
    if effect!=null:effect.set_screen_tiles(bool(state.get("screen_tiles",false)))
    super._apply()
func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("values",{}) is Dictionary:
        if request.get("values",{}).has("screen_tiles") and not request["values"]["screen_tiles"] is bool:return {"ok":false,"error":"screen_tiles_type","revision":revision}
    return super.command(request)
func _mode_state(backup: Dictionary,mode: String) -> Dictionary:
    var values: Dictionary=backup.duplicate(true);values.merge(TILE_MODES[mode],true)
    values["kernel_mode"]="split";values["compact_shadows"]=false;values["visibility_stream"]=false;values["visibility_diagnostics"]=false
    return values
func _run_comparison(quick: bool) -> void:
    hardware.release_counters();hardware_profile={}
    var backup: Dictionary=state.duplicate(true);var events: Array=[];var warmup: Array=[];var all_events: Array=[];var rows: Array=[];var seen: Dictionary={};var boundaries: Array=[];var error: String=""
    var rounds: int=1 if quick else 4;var modes: Array=TILE_MODES.keys()
    # Four rotations place every mode in each block slot exactly once.
    # Setup and all nine warm-up events stay separately classified.
    for cycle in range(rounds):
        var order: Array=[]
        for offset in range(modes.size()):order.append(modes[(cycle+offset)%modes.size()])
        for mode in order:
            if _benchmark_cancelled or error!="":break
            var reset: Dictionary=_mode_state(backup,mode)
            boundaries.append({"mode":mode,"cycle":cycle,"boundary":"before_block","telemetry":hardware.telemetry()})
            var event: Dictionary=await _stream_event(reset,"initial_geometry",mode,cycle,true)
            if event.has("error"):
                if not _benchmark_cancelled:error=event["error"]
                break
            warmup.append(event);all_events.append(event)
            for trial in _diagnostic_trials(reset):
                if _benchmark_cancelled:break
                if _benchmark_status!=null:_benchmark_status.text="Preparando %s · %s" % [TILE_LABELS[mode],trial["kind"]]
                event=await _stream_event(trial["values"],trial["kind"],mode,cycle)
                if event.has("error"):
                    if not _benchmark_cancelled:error=event["error"]
                    break
                warmup.append(event);all_events.append(event)
            if _benchmark_cancelled or error!="":_comparison_collect(all_events,rows,seen);break
            for trial in _diagnostic_trials(reset):
                if _benchmark_cancelled:break
                if _benchmark_status!=null:_benchmark_status.text="Midiendo %s · %s · %d/%d" % [TILE_LABELS[mode],trial["kind"],events.size()+1,rounds*36]
                event=await _stream_event(trial["values"],trial["kind"],mode,cycle)
                if event.has("error"):
                    if not _benchmark_cancelled:error=event["error"]
                    break
                events.append(event);all_events.append(event)
            _comparison_collect(all_events,rows,seen)
            boundaries.append({"mode":mode,"cycle":cycle,"boundary":"after_block","telemetry":hardware.telemetry()})
    for drain in range(8):await get_tree().process_frame
    _comparison_collect(all_events,rows,seen)
    var summary: Array=_stream_summary(rows,events);var warmup_summary: Array=[]
    for group in _stream_summary(rows,warmup):warmup_summary.append({"mode":group["mode"],"kind":group["kind"],"gpu":group["gpu"]})
    var work: Array=[]
    if not _benchmark_cancelled and error=="":work=await _measure_stream_work(backup)
    if not _benchmark_cancelled and error=="":hardware_profile=await _measure_hardware(backup)
    hardware.release_counters()
    var restore: Dictionary=_benchmark_set_values(backup)
    _comparison_report={"schema":"lie-screen-tile-comparison/1","scene":backup,"rounds":rounds,"modes":TILE_MODES,"events":events,"warmup_events":warmup,"warmup_summary":warmup_summary,"summary":summary,"passes":{"rows":rows},"work_diagnostic":work,"hardware_profile":hardware_profile,"telemetry_boundaries":boundaries,"expected_events":rounds*36,"cancelled":_benchmark_cancelled,"error":error,"restored":restore["ok"] and state==backup,"scope":"Four isolated modes with identical scene and original 80-byte source bank. Four rotated rounds balance block slots; initial geometry and nine fixed warm-ups separately retained per block. All measured events and spikes retained; no timed GPU readbacks or hardware sampling. Separate work probes compare bounds through the same stream kernel. Separate whole-device counters compare reference/combined; not per-pass. Thermal/frequency uncontrolled. Display FPS includes cached images."}
    _persist_report("user://lie-screen-tiles-last.json",_comparison_report);benchmark_busy=false
    if _benchmark_status!=null:_benchmark_status.text="Comparación cancelada; estado restaurado" if _benchmark_cancelled else "Comparación terminada; pulsa Informe" if error=="" else "Comparación incompleta: "+error
func _hardware_modes() -> Dictionary:
    var result: Dictionary={}
    for mode in ["reference","combined"]:
        var values: Dictionary=TILE_MODES[mode].duplicate();values["compact_shadows"]=false;result[mode]=values
    return result
func _measure_stream_work(backup: Dictionary) -> Array:
    var result: Array=[]
    for mode in ["reference","tight"]:
        var values: Dictionary=_mode_state(backup,mode);values["visibility_stream"]=true;values["active_visibility"]=true;values["visibility_diagnostics"]=true
        var setup: Dictionary=await _stream_event(values,"work_setup",mode,-1,true)
        if setup.has("error"):return result
        for delta in [8.,-8.,0.]:
            if _benchmark_cancelled:break
            var update: Dictionary={"light_azimuth":wrapf(float(backup["light_azimuth"])+delta,-180.,180.)}
            var event: Dictionary=await _stream_event(update,"work_light_position",mode,-1)
            if event.has("error"):return result
            effect.request_work_counters()
            for waited in range(120):
                await get_tree().process_frame
                if not effect.work_counters().is_empty():break
            result.append({"mode":mode,"values":update,"counters":effect.work_counters(),"untimed":true})
    return result
func _build_report() -> Dictionary:
    var result: Dictionary=super._build_report();result["app_version"]="1.9.0-screen-tiles";return result
func _portable_report(report: Dictionary) -> Dictionary:
    var result: Dictionary=super._portable_report(report);result["cache"]["screen_tiles"]=report["cache"]["screen_tiles"]
    var comparison: Dictionary=result.get("kernel_comparison",{})
    if not comparison.is_empty():
        comparison["modes"]=TILE_MODES;comparison.erase("telemetry_boundaries")
        comparison.erase("warmup_summary")
        for group in comparison["summary"]:
            var stages: Dictionary={}
            for name in group["passes"]:stages[name]=group["passes"][name]["p50_ms"]
            group["pass_p50_ms"]=stages;group.erase("passes")
    result["copy_scope"]="Four-mode timing summary; full events, warm-up, per-stage tails and telemetry in lie-screen-tiles-last.json and lie-performance-last.json"
    return result
func _report_header(report: Dictionary) -> String:
    var comparison: Dictionary=report.get("kernel_comparison",{})
    if comparison.is_empty():return super._report_header(report).replace("LIE 1.8.1","LIE 1.9")
    var text: String="LIE 1.9 · BLOQUES Y LÍMITES\n%s · %s\n" % [report["device"],report["gpu"]]
    for kind in ["camera","light_power","light_position"]:
        text+="\n"+{"camera":"Cámara","light_power":"Potencia","light_position":"Posición de luz"}[kind]
        for mode in TILE_MODES:
            for group in comparison["summary"]:
                if group["kind"]==kind and group["mode"]==mode:text+="\n%s: %.2f ms · %d eventos" % [TILE_LABELS[mode],group["gpu"]["p50_ms"],group["gpu"]["samples"]]
    var profile: Dictionary=comparison.get("hardware_profile",{})
    text+="\n\nContadores: %d/6 intervalos corroborados" % int(profile.get("valid_blocks",0))
    if not profile.get("status",{}).get("available",false):text+=" · "+str(profile.get("status",{}).get("reason","no disponibles"))
    return text+"\nMisma escena. Calentamiento separado; todos los picos conservados.\n\n"
func _ui() -> void:
    super._ui();_check(status.get_parent(),"screen_tiles","Cobertura por bloques de pantalla")
    for item in picture.get_parent().get_children():
        if item is Label and item.text.begins_with("LIE ·"):item.text="LIE · Bloques y límites · 1.9"
func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot();result["control_contract"]["booleans"].append("screen_tiles");result["control_contract"]["comparison_modes"]=TILE_MODES;return result
