extends "res://lie_wall17_android_lab.gd"
const StreamEffect=preload("res://lie_wall19_stream_effect.gd")
func _ready() -> void:
    state["visibility_stream"]=false;super._ready()
func _coded_effect_factory() -> CompositorEffect:return StreamEffect.new(720)
func _apply() -> void:
    if effect!=null:effect.set_visibility_stream(bool(state.get("visibility_stream",false)))
    super._apply()
func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("values",{}) is Dictionary:
        if request.get("values",{}).has("visibility_stream") and not request["values"]["visibility_stream"] is bool:return {"ok":false,"error":"visibility_stream_type","revision":revision}
    return super.command(request)
func _stream_event(values: Dictionary,kind: String,mode: String,cycle: int,force: bool=false) -> Dictionary:
    var before: int=effect.frame_count;var begin: int=Time.get_ticks_usec()
    var result: Dictionary=_benchmark_set_values(values);var cpu_ms: float=float(Time.get_ticks_usec()-begin)/1000.
    if not result["ok"]:return {"error":str(result)}
    if force:effect.prepare_stream_comparison()
    if not await _comparison_wait(before):return {"error":"cancelled" if _benchmark_cancelled else "render_timeout"}
    return {"mode":mode,"cycle":cycle,"kind":kind,"values":values.duplicate(true),"serial":effect.frame_count,"cpu_command_ms":cpu_ms}
func _stream_summary(rows: Array,events: Array) -> Array:
    var kinds: Dictionary={};var selected: Dictionary={}
    for event in events:kinds[int(event["serial"])]=event["kind"];selected[int(event["serial"])]=event
    var filtered: Array=[]
    for row in rows:
        if selected.has(int(row["serial"])):filtered.append(row)
    var analysis: Dictionary=Diagnostics.summarize({"rows":filtered},0,kinds);var summary: Array=[]
    for group in analysis["groups"]:
        var cpu: Array=[];var modes: Dictionary={}
        for serial in group["serials"]:cpu.append(selected[serial]["cpu_command_ms"]);modes[selected[serial]["mode"]]=true
        var passes: Dictionary={}
        for entry in group["ranking"]:passes[entry["pass"]]={"p50_ms":entry["p50_ms"],"p95_ms":entry["p95_ms"],"samples":entry["samples"]}
        summary.append({"mode":modes.keys()[0],"kind":group["context"]["diagnostic_kind"],"gpu":group["total_instrumented_gpu"],"cpu":Diagnostics.percentiles(cpu),"passes":passes})
    return summary
func _run_comparison(quick: bool) -> void:
    var backup: Dictionary=state.duplicate(true);var events: Array=[];var warmup: Array=[];var all_events: Array=[];var rows: Array=[];var seen: Dictionary={};var error: String=""
    var rounds: int=1 if quick else 3
    for cycle in range(rounds):
        for offset in range(2):
            if _benchmark_cancelled or error!="":break
            var enabled: bool=(cycle+offset)%2==1;var mode: String="stream" if enabled else "reference"
            var reset: Dictionary=backup.duplicate(true);reset["kernel_mode"]="split";reset["visibility_stream"]=enabled;reset["visibility_diagnostics"]=false
            var event: Dictionary=await _stream_event(reset,"initial_geometry",mode,cycle,true)
            if event.has("error"):
                if not _benchmark_cancelled:error=event["error"]
                break
            warmup.append(event);all_events.append(event)
            # Warm every actual entry point, including recovery reuse. Retain
            # these events separately; never relabel an outlier after seeing it.
            for trial in _diagnostic_trials(reset):
                if _benchmark_cancelled:break
                if _benchmark_status!=null:_benchmark_status.text="Preparando %s · %s" % [mode,trial["kind"]]
                event=await _stream_event(trial["values"],trial["kind"],mode,cycle)
                if event.has("error"):
                    if not _benchmark_cancelled:error=event["error"]
                    break
                warmup.append(event);all_events.append(event)
            if _benchmark_cancelled or error!="":_comparison_collect(all_events,rows,seen);break
            for trial in _diagnostic_trials(reset):
                if _benchmark_cancelled:break
                if _benchmark_status!=null:_benchmark_status.text="Midiendo %s · %s · %d/%d" % [mode,trial["kind"],events.size()+1,rounds*18]
                event=await _stream_event(trial["values"],trial["kind"],mode,cycle)
                if event.has("error"):
                    if not _benchmark_cancelled:error=event["error"]
                    break
                events.append(event);all_events.append(event)
            _comparison_collect(all_events,rows,seen)
    for drain in range(8):await get_tree().process_frame
    _comparison_collect(all_events,rows,seen)
    var summary: Array=_stream_summary(rows,events);var warmup_groups: Array=_stream_summary(rows,warmup);var warmup_summary: Array=[]
    for group in warmup_groups:warmup_summary.append({"mode":group["mode"],"kind":group["kind"],"gpu":group["gpu"]})
    var work: Array=[]
    if not _benchmark_cancelled and error=="":work=await _measure_stream_work(backup)
    var restore: Dictionary=_benchmark_set_values(backup)
    _comparison_report={"schema":"lie-visibility-stream-comparison/1","scene":backup,"rounds":rounds,"events":events,"warmup_events":warmup,"warmup_summary":warmup_summary,"work_diagnostic":work,"summary":summary,"passes":{"rows":rows},"cancelled":_benchmark_cancelled,"error":error,"restored":restore["ok"] and state==backup,"expected_events":rounds*18,"scope":"Actual 1.4 versus ordered winner queues and separate per-light cache/witness/BLAS kernels; reference/stream order alternates; identical geometry/light sequence; private hints and visibility reset before setup; immutable query permutation retained; initial geometry plus all nine camera/power/position warm-up events recorded separately before each measured block. Warm-up classification is fixed before execution, with no outlier rejection. Timed events have no GPU reads. Separate instrumented work events read 32 counter bytes after timing; thermal state not controlled."}
    _persist_report("user://lie-visibility-stream-last.json",_comparison_report);benchmark_busy=false
    if _benchmark_status!=null:_benchmark_status.text="Comparación cancelada" if _benchmark_cancelled else "Error: "+error if error!="" else "Comparación lista · abre Informe"
func _build_report() -> Dictionary:
    var result: Dictionary=super._build_report();result["app_version"]="1.6.0-visibility-stream";result["scope"]="Timed comparison has no GPU reads; separate explicitly instrumented work events read 32 GPU counter bytes afterward. Display FPS includes cached images. Requested RID bytes are not measured VRAM/PSS.";return result
func _portable_report(report: Dictionary) -> Dictionary:
    var result: Dictionary=super._portable_report(report);result["cache"]["visibility_stream"]=report["cache"]["visibility_stream"]
    if not report.get("kernel_comparison",{}).is_empty():
        var original: Dictionary=report["kernel_comparison"];var compact: Dictionary=result["kernel_comparison"].duplicate(true)
        compact["scene"]=original["scene"];compact["work_diagnostic"]=original.get("work_diagnostic",[]);compact["warmup_summary"]=original["warmup_summary"];compact["warmup_recorded_events"]=original["warmup_events"].size()
        for group in compact["summary"]:
            for pass_name in group["passes"]:group["passes"][pass_name].erase("samples")
        result["kernel_comparison"]=compact
    return result
func _report_header(report: Dictionary) -> String:
    var comparison: Dictionary=report.get("kernel_comparison",{})
    if comparison.is_empty():return super._report_header(report).replace("LIE 1.4","LIE 1.6")
    var text: String="LIE 1.6 · COMPARACIÓN DE VISIBILIDAD\n%s · %s\n" % [report["device"],report["gpu"]]
    for kind in ["camera","light_power","light_position"]:
        text+="\n"+{"camera":"Cámara","light_power":"Potencia","light_position":"Posición de luz"}[kind]
        for mode in ["reference","stream"]:
            for group in comparison["summary"]:
                if group["kind"]==kind and group["mode"]==mode:text+="\n%s: %.2f ms · %d eventos" % ["1.4" if mode=="reference" else "1.6",group["gpu"]["p50_ms"],group["gpu"]["samples"]]
    return text+"\n\nMisma escena. Calentamiento registrado por separado; sin eliminar picos de la medición.\n\n"
func _ui() -> void:
    super._ui();var box: Node=status.get_parent();_label(box,"VISIBILIDAD GPU",19);_check(box,"visibility_stream","Agrupar y separar consultas de sombras")
    for item in picture.get_parent().get_children():
        if item is Label and item.text.begins_with("LIE ·"):item.text="LIE · Visibilidad por etapas · 1.6.0"
func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot();result["control_contract"]["booleans"].append("visibility_stream");return result

func _measure_stream_work(backup: Dictionary) -> Array:
    var values: Dictionary=backup.duplicate(true);values["kernel_mode"]="split";values["visibility_stream"]=true;values["active_visibility"]=true;values["visibility_diagnostics"]=true
    var setup: Dictionary=await _stream_event(values,"work_setup","stream",-1,true);var result: Array=[]
    if setup.has("error"):return result
    for delta in [8.,-8.,0.]:
        if _benchmark_cancelled:break
        var update: Dictionary={"light_azimuth":wrapf(float(backup["light_azimuth"])+delta,-180.,180.)}
        var event: Dictionary=await _stream_event(update,"work_light_position","stream",-1)
        if event.has("error"):break
        effect.request_work_counters()
        for waited in range(120):
            await get_tree().process_frame
            if not effect.work_counters().is_empty():break
        result.append({"values":update,"counters":effect.work_counters(),"untimed":true})
    return result
