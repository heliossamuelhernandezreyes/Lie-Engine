extends "res://lie_wall20_android_lab.gd"
const CompactEffect=preload("res://lie_wall21_compact_effect.gd")
const Hardware=preload("res://lie_hardware_diagnostics.gd")
var hardware:=Hardware.new()
var hardware_status: Dictionary={"available":false,"reason":"not_probed"}
var hardware_profile: Dictionary={}
func _ready() -> void:
    state["compact_shadows"]=false;super._ready()
func _coded_effect_factory() -> CompositorEffect:return CompactEffect.new(720)
func _apply() -> void:
    if effect!=null:effect.set_compact_shadows(bool(state.get("compact_shadows",false)))
    super._apply()
func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("op")=="gpu_probe":
        if request.size()!=1:return {"ok":false,"error":"probe_fields","revision":revision}
        if benchmark_busy:return {"ok":false,"error":"benchmark_busy","revision":revision}
        hardware_status=hardware.probe();hardware.release_counters()
        return {"ok":true,"hardware":hardware_status.duplicate(true),"telemetry":hardware.telemetry(),"revision":revision}
    if request is Dictionary and request.get("values",{}) is Dictionary:
        if request.get("values",{}).has("compact_shadows") and not request["values"]["compact_shadows"] is bool:return {"ok":false,"error":"compact_shadows_type","revision":revision}
    return super.command(request)
func _run_comparison(quick: bool) -> void:
    hardware.release_counters();hardware_profile={}
    var boundaries: Array=[]
    var backup: Dictionary=state.duplicate(true);var events: Array=[];var warmup: Array=[];var all_events: Array=[];var rows: Array=[];var seen: Dictionary={};var error: String=""
    var rounds: int=1 if quick else 3
    for cycle in range(rounds):
        for offset in range(2):
            if _benchmark_cancelled or error!="":break
            var enabled: bool=(cycle+offset)%2==1;var mode: String="compact" if enabled else "reference"
            var reset: Dictionary=backup.duplicate(true);reset["kernel_mode"]="split";reset["compact_shadows"]=enabled;reset["visibility_stream"]=false;reset["visibility_diagnostics"]=false
            boundaries.append({"mode":mode,"cycle":cycle,"boundary":"before_block","telemetry":hardware.telemetry()})
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
            boundaries.append({"mode":mode,"cycle":cycle,"boundary":"after_block","telemetry":hardware.telemetry()})
    for drain in range(8):await get_tree().process_frame
    _comparison_collect(all_events,rows,seen)
    var summary: Array=_stream_summary(rows,events);var warmup_groups: Array=_stream_summary(rows,warmup);var warmup_summary: Array=[]
    for group in warmup_groups:warmup_summary.append({"mode":group["mode"],"kind":group["kind"],"gpu":group["gpu"]})
    var work: Array=[]
    if not _benchmark_cancelled and error=="":work=await _measure_stream_work(backup)
    if not _benchmark_cancelled and error=="":hardware_profile=await _measure_hardware(backup)
    hardware.release_counters()
    var restore: Dictionary=_benchmark_set_values(backup)
    _comparison_report={"schema":"lie-gpu-diagnostics-comparison/1","telemetry_boundaries":boundaries,"hardware_profile":hardware_profile,"scene":backup,"rounds":rounds,"events":events,"warmup_events":warmup,"warmup_summary":warmup_summary,"work_diagnostic":work,"summary":summary,"passes":{"rows":rows},"cancelled":_benchmark_cancelled,"error":error,"restored":restore["ok"] and state==backup,"expected_events":rounds*18,"scope":"Identical disk equations, topology and bounds; original 80-byte versus exact 32-byte shadow view; reference/compact order alternates; stream scheduling OFF in both timed modes; identical geometry/light sequence; private hints and visibility reset before setup; initial geometry plus all nine camera/power/position warm-up events recorded separately before each measured block. Warm-up classification is fixed before execution, with no outlier rejection. Timed events have no GPU reads. Separate instrumented work events read 32 counter bytes per separate work event after timing; hardware counter intervals collected only after timed/work events; best-effort frequency/thermal telemetry outside event timing; thermal state not controlled. Callback wait is not GPU completion or input-to-photon latency."}
    _persist_report("user://lie-gpu-diagnostics-last.json",_comparison_report);benchmark_busy=false
    if _benchmark_status!=null:_benchmark_status.text="Comparación cancelada" if _benchmark_cancelled else "Error: "+error if error!="" else "Comparación lista · abre Informe"
func _build_report() -> Dictionary:
    var result: Dictionary=super._build_report();result["app_version"]="1.8.0-gpu-diagnostics";result["hardware_status"]=hardware_status;result["scope"]="Timed comparison has no GPU reads; separate explicitly instrumented work events read 32 GPU counter bytes afterward. Display FPS includes cached images. Requested RID bytes are not measured VRAM/PSS.";return result
func _portable_report(report: Dictionary) -> Dictionary:
    var result: Dictionary=super._portable_report(report);result["cache"]["compact_shadows"]=report["cache"]["compact_shadows"];result["hardware_status"]=report["hardware_status"]
    if not report.get("kernel_comparison",{}).is_empty():
        var original: Dictionary=report["kernel_comparison"];var compact: Dictionary=result["kernel_comparison"].duplicate(true)
        compact["hardware_profile"]=_compact_hardware(original.get("hardware_profile",{}));compact["telemetry_boundaries"]=original.get("telemetry_boundaries",[]);compact["scene"]=original["scene"];compact["work_diagnostic"]=original.get("work_diagnostic",[]);compact["warmup_summary"]=original["warmup_summary"];compact["warmup_recorded_events"]=original["warmup_events"].size()
        for group in compact["summary"]:
            for pass_name in group["passes"]:group["passes"][pass_name].erase("samples")
        result["kernel_comparison"]=compact
    return result
func _report_header(report: Dictionary) -> String:
    var comparison: Dictionary=report.get("kernel_comparison",{})
    if comparison.is_empty():return super._report_header(report).replace("LIE 1.7","LIE 1.8")
    var text: String="LIE 1.8 · DATOS Y DIAGNÓSTICO GPU\n%s · %s\n" % [report["device"],report["gpu"]]
    for kind in ["camera","light_power","light_position"]:
        text+="\n"+{"camera":"Cámara","light_power":"Potencia","light_position":"Posición de luz"}[kind]
        for mode in ["reference","compact"]:
            for group in comparison["summary"]:
                if group["kind"]==kind and group["mode"]==mode:text+="\n%s: %.2f ms · %d eventos" % ["80 B" if mode=="reference" else "32 B",group["gpu"]["p50_ms"],group["gpu"]["samples"]]
    text+="\n\nContadores GPU: "+("disponibles" if comparison.get("hardware_profile",{}).get("status",{}).get("available",false) else "no disponibles · "+str(comparison.get("hardware_profile",{}).get("status",{}).get("reason","sin diagnóstico")))
    return text+"\n\nMisma escena. Calentamiento registrado por separado; sin eliminar picos de la medición.\n\n"
func _ui() -> void:
    super._ui()
    var box: Node=status.get_parent()
    _check(box,"compact_shadows","Datos compactos para sombras")
    var probe_button:=Button.new();probe_button.text="Diagnóstico GPU";box.add_child(probe_button)
    probe_button.pressed.connect(func():
        var result: Dictionary=command({"op":"gpu_probe"})
        if result["ok"]:status.text="Contadores GPU disponibles" if hardware_status.get("available",false) else "Contadores: "+str(hardware_status.get("reason","no disponibles")))
    for item in picture.get_parent().get_children():
        if item is Label and item.text.begins_with("LIE ·"):item.text="LIE · Diagnóstico GPU · 1.8.0"
func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot();result["control_contract"]["booleans"].append("compact_shadows");return result

func _exit_tree() -> void:hardware.release_counters()
func _stream_event(values: Dictionary,kind: String,mode: String,cycle: int,force: bool=false) -> Dictionary:
    var begin: int=Time.get_ticks_usec()
    var event: Dictionary=await super._stream_event(values,kind,mode,cycle,force)
    event["host_begin_us"]=begin;event["host_end_us"]=Time.get_ticks_usec()
    event["callback_wait_ms"]=float(Time.get_ticks_usec()-begin)/1000.
    event["callback_scope"]="command plus render callback and six-frame drain; not GPU completion or presentation"
    return event
func _measure_hardware(backup: Dictionary) -> Dictionary:
    hardware_status=hardware.probe()
    var result: Dictionary={"status":hardware_status.duplicate(true),"blocks":[],"telemetry":hardware.telemetry(),"scope":"separate untimed whole-device intervals; may include other apps, engine and presentation; not per-pass counters or input-to-photon latency"}
    if not hardware_status.get("available",false):hardware.release_counters();return result
    for enabled in [false,true]:
        var mode: String="compact" if enabled else "reference"
        for kind in ["camera","light_power","light_position"]:
            if _benchmark_cancelled:break
            var reset: Dictionary=backup.duplicate(true);reset["compact_shadows"]=enabled;reset["kernel_mode"]="split";reset["visibility_stream"]=false;reset["visibility_diagnostics"]=false
            var setup: Dictionary=await _stream_event(reset,"hardware_setup",mode,-2,true)
            if setup.has("error"):result["error"]=setup["error"];hardware.release_counters();return result
            for trial in _diagnostic_trials(reset):
                var warm: Dictionary=await _stream_event(trial["values"],trial["kind"],mode,-2)
                if warm.has("error"):result["error"]=warm["error"];hardware.release_counters();return result
            var before: Dictionary=hardware.telemetry();var started: Dictionary=hardware.begin()
            if not started.get("available",false):result["status"]["available"]=false;result["status"]["reason"]=started.get("reason","sampling start failed");result["begin_failure"]=started;hardware.release_counters();return result
            var events: Array=[]
            for trial in _diagnostic_trials(reset):
                if trial["kind"]!=kind:continue
                var event: Dictionary=await _stream_event(trial["values"],kind,mode,-2)
                events.append(event)
                if event.has("error"):break
            var sample: Dictionary=hardware.end()
            result["blocks"].append({"mode":mode,"kind":kind,"events":events,"sample":sample,"telemetry_before":before,"telemetry_after":hardware.telemetry()})
            if not sample.get("available",false):result["status"]["available"]=false;result["status"]["reason"]=sample.get("reason",sample.get("stop_error","sampling failed"));hardware.release_counters();return result
    hardware.release_counters();return result
func _compact_hardware(profile: Dictionary) -> Dictionary:
    var result: Dictionary=profile.duplicate(true)
    for block in result.get("blocks",[]):
        var serials: Array=[]
        for event in block["events"]:serials.append(event.get("serial",-1))
        block["serials"]=serials;block.erase("events")
        for name in block["sample"].get("counters",{}):
            var row: Dictionary=block["sample"]["counters"][name];row.erase("timestamp_ns");row.erase("unit")
    return result

func _measure_stream_work(backup: Dictionary) -> Array:
    var result: Array=[]
    # Both work probes use the identical instrumented 1.6 scheduling path.
    # These observations are separate from the timed original-1.4 kernels.
    for enabled in [false,true]:
        var values: Dictionary=backup.duplicate(true);values["kernel_mode"]="split";values["visibility_stream"]=true;values["active_visibility"]=true;values["visibility_diagnostics"]=true;values["compact_shadows"]=enabled
        var mode: String="compact" if enabled else "reference"
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
