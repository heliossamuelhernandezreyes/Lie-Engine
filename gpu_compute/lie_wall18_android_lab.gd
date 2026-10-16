extends "res://lie_wall17_android_lab.gd"
const PageEffect=preload("res://lie_wall18_pages_effect.gd")
func _ready() -> void:
    state["spatial_pages"]=true;super._ready()
func _coded_effect_factory() -> CompositorEffect:return PageEffect.new(720)
func _apply() -> void:
    if effect!=null:effect.set_spatial_pages(bool(state.get("spatial_pages",true)))
    super._apply()
func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("values",{}) is Dictionary:
        if request.get("values",{}).has("spatial_pages") and not request["values"]["spatial_pages"] is bool:return {"ok":false,"error":"spatial_pages_type","revision":revision}
    return super.command(request)
func _page_event(values: Dictionary,kind: String,mode: String,cycle: int,force: bool=false) -> Dictionary:
    var before: int=effect.frame_count;var begin: int=Time.get_ticks_usec()
    var result: Dictionary=_benchmark_set_values(values);var cpu_ms: float=float(Time.get_ticks_usec()-begin)/1000.
    if not result["ok"]:return {"error":str(result)}
    if force:effect.prepare_page_comparison()
    if not await _comparison_wait(before):return {"error":"cancelled" if _benchmark_cancelled else "render_timeout"}
    return {"mode":mode,"cycle":cycle,"kind":kind,"values":values.duplicate(true),"serial":effect.frame_count,"cpu_command_ms":cpu_ms}
func _page_summary(rows: Array,events: Array) -> Array:
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
            var enabled: bool=(cycle+offset)%2==1;var mode: String="pages_on" if enabled else "pages_off"
            var reset: Dictionary=backup.duplicate(true);reset["kernel_mode"]="split";reset["spatial_pages"]=enabled;reset["visibility_diagnostics"]=false
            var event: Dictionary=await _page_event(reset,"initial_geometry",mode,cycle,true)
            if event.has("error"):
                if not _benchmark_cancelled:error=event["error"]
                break
            warmup.append(event);all_events.append(event)
            # Warm every actual entry point, including recovery reuse. Retain
            # these events separately; never relabel an outlier after seeing it.
            for trial in _diagnostic_trials(reset):
                if _benchmark_cancelled:break
                if _benchmark_status!=null:_benchmark_status.text="Preparando %s · %s" % [mode,trial["kind"]]
                event=await _page_event(trial["values"],trial["kind"],mode,cycle)
                if event.has("error"):
                    if not _benchmark_cancelled:error=event["error"]
                    break
                warmup.append(event);all_events.append(event)
            if _benchmark_cancelled or error!="":_comparison_collect(all_events,rows,seen);break
            for trial in _diagnostic_trials(reset):
                if _benchmark_cancelled:break
                if _benchmark_status!=null:_benchmark_status.text="Midiendo %s · %s · %d/%d" % [mode,trial["kind"],events.size()+1,rounds*18]
                event=await _page_event(trial["values"],trial["kind"],mode,cycle)
                if event.has("error"):
                    if not _benchmark_cancelled:error=event["error"]
                    break
                events.append(event);all_events.append(event)
            _comparison_collect(all_events,rows,seen)
    for drain in range(8):await get_tree().process_frame
    _comparison_collect(all_events,rows,seen)
    var summary: Array=_page_summary(rows,events);var warmup_groups: Array=_page_summary(rows,warmup);var warmup_summary: Array=[]
    for group in warmup_groups:warmup_summary.append({"mode":group["mode"],"kind":group["kind"],"gpu":group["gpu"]})
    var restore: Dictionary=_benchmark_set_values(backup)
    _comparison_report={"schema":"lie-spatial-page-comparison/1","scene":backup,"rounds":rounds,"events":events,"warmup_events":warmup,"warmup_summary":warmup_summary,"summary":summary,"passes":{"rows":rows},"cancelled":_benchmark_cancelled,"error":error,"restored":restore["ok"] and state==backup,"expected_events":rounds*18,"scope":"Same 1.4 dedicated kernels except the addressed visibility kernel; pages OFF/ON order alternates; identical geometry/light sequence; private hints and visibility reset before setup; immutable pages retained; initial geometry plus all nine camera/power/position warm-up events recorded separately before each measured block. Warm-up classification is fixed before execution, with no outlier rejection. No GPU buffer/image readbacks; thermal state not controlled."}
    _persist_report("user://lie-spatial-pages-last.json",_comparison_report);benchmark_busy=false
    if _benchmark_status!=null:_benchmark_status.text="Comparación cancelada" if _benchmark_cancelled else "Error: "+error if error!="" else "Comparación lista · abre Informe"
func _build_report() -> Dictionary:
    var result: Dictionary=super._build_report();result["app_version"]="1.5.0-spatial-pages";return result
func _portable_report(report: Dictionary) -> Dictionary:
    var result: Dictionary=super._portable_report(report);result["cache"]["spatial_pages"]=report["cache"]["spatial_pages"]
    if not report.get("kernel_comparison",{}).is_empty():
        var original: Dictionary=report["kernel_comparison"];var compact: Dictionary=result["kernel_comparison"].duplicate(true)
        compact["scene"]=original["scene"];compact["warmup_summary"]=original["warmup_summary"];compact["warmup_recorded_events"]=original["warmup_events"].size()
        for group in compact["summary"]:
            for pass_name in group["passes"]:group["passes"][pass_name].erase("samples")
        result["kernel_comparison"]=compact
    return result
func _report_header(report: Dictionary) -> String:
    var comparison: Dictionary=report.get("kernel_comparison",{})
    if comparison.is_empty():return super._report_header(report).replace("LIE 1.4","LIE 1.5")
    var text: String="LIE 1.5 · COMPARACIÓN DE PÁGINAS\n%s · %s\n" % [report["device"],report["gpu"]]
    for kind in ["camera","light_power","light_position"]:
        text+="\n"+{"camera":"Cámara","light_power":"Potencia","light_position":"Posición de luz"}[kind]
        for mode in ["pages_off","pages_on"]:
            for group in comparison["summary"]:
                if group["kind"]==kind and group["mode"]==mode:text+="\n%s: %.2f ms · %d eventos" % ["1.4" if mode=="pages_off" else "1.5",group["gpu"]["p50_ms"],group["gpu"]["samples"]]
    return text+"\n\nMisma escena. Calentamiento registrado por separado; sin eliminar picos de la medición.\n\n"
func _ui() -> void:
    super._ui();var box: Node=status.get_parent();_label(box,"PÁGINAS ESPACIALES",19);_check(box,"spatial_pages","Acceder a muestras por coordenadas")
    for item in picture.get_parent().get_children():
        if item is Label and item.text.begins_with("LIE ·"):item.text="LIE · Páginas espaciales · 1.5.0"
func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot();result["control_contract"]["booleans"].append("spatial_pages");return result
