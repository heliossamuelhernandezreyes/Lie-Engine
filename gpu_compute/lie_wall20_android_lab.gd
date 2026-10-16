extends "res://lie_wall19_android_lab.gd"
const BoundsEffect=preload("res://lie_wall20_bounds_effect.gd")
func _ready() -> void:
    state["tight_bounds"]=false;super._ready()
func _coded_effect_factory() -> CompositorEffect:return BoundsEffect.new(720)
func _apply() -> void:
    if effect!=null:effect.set_tight_bounds(bool(state.get("tight_bounds",false)))
    super._apply()
func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("values",{}) is Dictionary:
        if request.get("values",{}).has("tight_bounds") and not request["values"]["tight_bounds"] is bool:return {"ok":false,"error":"tight_bounds_type","revision":revision}
    return super.command(request)
func _run_comparison(quick: bool) -> void:
    var backup: Dictionary=state.duplicate(true);var events: Array=[];var warmup: Array=[];var all_events: Array=[];var rows: Array=[];var seen: Dictionary={};var error: String=""
    var rounds: int=1 if quick else 3
    for cycle in range(rounds):
        for offset in range(2):
            if _benchmark_cancelled or error!="":break
            var enabled: bool=(cycle+offset)%2==1;var mode: String="tight" if enabled else "reference"
            var reset: Dictionary=backup.duplicate(true);reset["kernel_mode"]="split";reset["tight_bounds"]=enabled;reset["visibility_stream"]=false;reset["visibility_diagnostics"]=false
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
    _comparison_report={"schema":"lie-tangent-bounds-comparison/1","scene":backup,"rounds":rounds,"events":events,"warmup_events":warmup,"warmup_summary":warmup_summary,"work_diagnostic":work,"summary":summary,"passes":{"rows":rows},"cancelled":_benchmark_cancelled,"error":error,"restored":restore["ok"] and state==backup,"expected_events":rounds*18,"scope":"Actual 1.4 kernels and source topology, original sphere bounds versus refitted tangent-disk bounds; reference/tight order alternates; stream scheduling OFF in both timed modes; identical geometry/light sequence; private hints and visibility reset before setup; initial geometry plus all nine camera/power/position warm-up events recorded separately before each measured block. Warm-up classification is fixed before execution, with no outlier rejection. Timed events have no GPU reads. Separate instrumented work events read 32 counter bytes per separate work event after timing; thermal state not controlled."}
    _persist_report("user://lie-tangent-bounds-last.json",_comparison_report);benchmark_busy=false
    if _benchmark_status!=null:_benchmark_status.text="Comparación cancelada" if _benchmark_cancelled else "Error: "+error if error!="" else "Comparación lista · abre Informe"
func _build_report() -> Dictionary:
    var result: Dictionary=super._build_report();result["app_version"]="1.7.0-tangent-bounds";result["scope"]="Timed comparison has no GPU reads; separate explicitly instrumented work events read 32 GPU counter bytes afterward. Display FPS includes cached images. Requested RID bytes are not measured VRAM/PSS.";return result
func _portable_report(report: Dictionary) -> Dictionary:
    var result: Dictionary=super._portable_report(report);result["cache"]["tangent_bounds"]=report["cache"]["tangent_bounds"]
    if not report.get("kernel_comparison",{}).is_empty():
        var original: Dictionary=report["kernel_comparison"];var compact: Dictionary=result["kernel_comparison"].duplicate(true)
        compact["scene"]=original["scene"];compact["work_diagnostic"]=original.get("work_diagnostic",[]);compact["warmup_summary"]=original["warmup_summary"];compact["warmup_recorded_events"]=original["warmup_events"].size()
        for group in compact["summary"]:
            for pass_name in group["passes"]:group["passes"][pass_name].erase("samples")
        result["kernel_comparison"]=compact
    return result
func _report_header(report: Dictionary) -> String:
    var comparison: Dictionary=report.get("kernel_comparison",{})
    if comparison.is_empty():return super._report_header(report).replace("LIE 1.6","LIE 1.7")
    var text: String="LIE 1.7 · COMPARACIÓN DE LÍMITES\n%s · %s\n" % [report["device"],report["gpu"]]
    for kind in ["camera","light_power","light_position"]:
        text+="\n"+{"camera":"Cámara","light_power":"Potencia","light_position":"Posición de luz"}[kind]
        for mode in ["reference","tight"]:
            for group in comparison["summary"]:
                if group["kind"]==kind and group["mode"]==mode:text+="\n%s: %.2f ms · %d eventos" % ["1.4" if mode=="reference" else "1.7",group["gpu"]["p50_ms"],group["gpu"]["samples"]]
    return text+"\n\nMisma escena. Calentamiento registrado por separado; sin eliminar picos de la medición.\n\n"
func _ui() -> void:
    super._ui()
    var box: Node=status.get_parent()
    for item in box.get_children():
        if item is BaseButton and item.text=="Agrupar y separar consultas de sombras":item.visible=false
    _check(box,"tight_bounds","Ajustar cajas a los discos")
    for item in picture.get_parent().get_children():
        if item is Label and item.text.begins_with("LIE ·"):item.text="LIE · Límites de discos · 1.7.0"
func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot();result["control_contract"]["booleans"].append("tight_bounds");return result

func _measure_stream_work(backup: Dictionary) -> Array:
    var result: Array=[]
    # Both work probes use the identical instrumented 1.6 scheduling path.
    # These observations are separate from the timed original-1.4 kernels.
    for enabled in [false,true]:
        var values: Dictionary=backup.duplicate(true);values["kernel_mode"]="split";values["visibility_stream"]=true;values["active_visibility"]=true;values["visibility_diagnostics"]=true;values["tight_bounds"]=enabled
        var mode: String="tight" if enabled else "reference"
        var setup: Dictionary=await _stream_event(values,"work_setup",mode,-1,true)
        if setup.has("error"):return result
        for delta in [8.,-8.,0.]:
            if _benchmark_cancelled:break
            var update: Dictionary={"light_azimuth":wrapf(float(backup["light_azimuth"])+delta,-180.,180.)}
            var event: Dictionary=await _stream_event(update,"work_light_position",mode,-1)
            if event.has("error"):break
            effect.request_work_counters()
            for waited in range(120):
                await get_tree().process_frame
                if not effect.work_counters().is_empty():break
            result.append({"mode":mode,"values":update,"counters":effect.work_counters(),"untimed":true})
    return result
