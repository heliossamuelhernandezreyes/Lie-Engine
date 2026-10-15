extends "res://lie_wall16_android_lab.gd"
const KernelEffect=preload("res://lie_wall17_kernel_effect.gd")
const KERNEL_MODES=["legacy","monolithic","split"]
var _kernel_picker: OptionButton
var _comparison_report: Dictionary={}
func _ready() -> void:
    state["kernel_mode"]="split";super._ready()
func _coded_effect_factory() -> CompositorEffect:return KernelEffect.new(720)
func _apply() -> void:
    if effect!=null:effect.set_kernel_mode(str(state.get("kernel_mode","split")))
    super._apply()
func _refresh() -> void:
    super._refresh()
    if _kernel_picker!=null:_kernel_picker.select(KERNEL_MODES.find(state["kernel_mode"]))
func command(request: Variant) -> Dictionary:
    if request is Dictionary:
        if request.get("op")=="compare_kernels":
            for key in request:
                if key not in ["op","quick"]:return {"ok":false,"error":"comparison_fields","revision":revision}
            if request.has("quick") and not request["quick"] is bool:return {"ok":false,"error":"quick_type","revision":revision}
            if benchmark_busy:return {"ok":false,"error":"benchmark_busy","revision":revision}
            benchmark_busy=true;_benchmark_cancelled=false;_clear_gesture();_run_comparison.call_deferred(bool(request.get("quick",false)))
            return {"ok":true,"revision":revision}
        if request.get("values",{}) is Dictionary:
            var values: Dictionary=request.get("values",{})
            if values.has("kernel_mode") and (not values["kernel_mode"] is String or values["kernel_mode"] not in KERNEL_MODES):return {"ok":false,"error":"kernel_mode","revision":revision}
    return super.command(request)
func _comparison_wait(before: int) -> bool:
    for waited in range(600):
        if _benchmark_cancelled:return false
        if effect.frame_count>before:
            for drain in range(6):await get_tree().process_frame
            return true
        await get_tree().process_frame
    return false
func _run_comparison(quick: bool) -> void:
    var backup: Dictionary=state.duplicate(true);var events: Array=[];var error: String=""
    var profile_start: int=effect.frame_count+1
    var rounds: int=1 if quick else 3
    # Rotate order to distribute warm-up and drift; this is not temperature control.
    for cycle in range(rounds):
        for offset in range(3):
            if _benchmark_cancelled or error!="":break
            var mode: String=KERNEL_MODES[(cycle+offset)%3]
            var reset: Dictionary=backup.duplicate(true);reset["kernel_mode"]=mode;reset["visibility_diagnostics"]=false
            var before: int=effect.frame_count
            var outcome: Dictionary=_benchmark_set_values(reset)
            if not outcome["ok"]:error=str(outcome);break
            effect.force_geometry_rebuild();effect.clear_visibility_cache()
            if not await _comparison_wait(before):
                if not _benchmark_cancelled:error="warmup_timeout"
                break
            # Identical event sequence from the identical camera/light state.
            for trial in _diagnostic_trials(reset):
                if _benchmark_cancelled:break
                if _benchmark_status!=null:_benchmark_status.text="Comparando %s · %s · %d/%d" % [mode,trial["kind"],events.size()+1,rounds*27]
                before=effect.frame_count
                var begin: int=Time.get_ticks_usec();outcome=_benchmark_set_values(trial["values"])
                var cpu_ms: float=float(Time.get_ticks_usec()-begin)/1000.
                if not outcome["ok"]:error=str(outcome);break
                if not await _comparison_wait(before):
                    if not _benchmark_cancelled:error="render_timeout"
                    break
                events.append({"mode":mode,"cycle":cycle,"kind":trial["kind"],"values":trial["values"].duplicate(true),"serial":effect.frame_count,"cpu_command_ms":cpu_ms})
    for drain in range(8):await get_tree().process_frame
    var selected: Dictionary={};var kinds: Dictionary={}
    for event in events:selected[int(event["serial"])]=true;kinds[int(event["serial"])]=event["kind"]
    var profile: Dictionary=effect.pass_profile.snapshot();var rows: Array=[]
    for row in profile.get("rows",[]):
        if selected.has(int(row["serial"])):rows.append(row)
    var analysis: Dictionary=Diagnostics.summarize({"rows":rows},profile_start,kinds)
    var summary: Array=[]
    for group in analysis["groups"]:
        var cpu: Array=[];var context: Dictionary=group["context"]
        for event in events:
            if event["serial"] in group["serials"]:cpu.append(event["cpu_command_ms"])
        var passes: Dictionary={}
        for entry in group["ranking"]:passes[entry["pass"]]={"p50_ms":entry["p50_ms"],"p95_ms":entry["p95_ms"],"samples":entry["samples"]}
        summary.append({"mode":context.get("kernel_mode","unknown"),"kind":context.get("diagnostic_kind","unknown"),"gpu":group["total_instrumented_gpu"],"cpu":Diagnostics.percentiles(cpu),"passes":passes})
    var restore: Dictionary=_benchmark_set_values(backup)
    _comparison_report={"schema":"lie-kernel-comparison/1","scene":backup,"rounds":rounds,"events":events,"summary":summary,"gpu_analysis":analysis,"passes":{"rows":rows},"cancelled":_benchmark_cancelled,"error":error,"restored":restore["ok"] and state==backup,"expected_events":rounds*27,"scope":"Same scene/options and nine-event sequence per variant; rotated mode order; one unmeasured cold rebuild per block; unchanged light stays cached within a block. No image/buffer readbacks; CPU command time is not GPU completion. Thermal state is not controlled."}
    _persist_report("user://lie-kernel-comparison-last.json",_comparison_report)
    benchmark_busy=false
    if _benchmark_status!=null:_benchmark_status.text="Comparación cancelada" if _benchmark_cancelled else "Error: "+error if error!="" else "Comparación lista · abre Informe"
func _build_report() -> Dictionary:
    var result: Dictionary=super._build_report();result["app_version"]="1.4.0-stage-kernels";result["kernel_comparison"]=_comparison_report.duplicate(true)
    return result
func _portable_report(report: Dictionary) -> Dictionary:
    var result: Dictionary=super._portable_report(report);result["cache"]["kernels"]=report["cache"]["kernels"]
    if not report.get("kernel_comparison",{}).is_empty():
        var comparison: Dictionary=report["kernel_comparison"];var compact: Dictionary={}
        for key in ["schema","rounds","summary","cancelled","error","restored","expected_events","scope"]:compact[key]=comparison[key]
        compact["recorded_events"]=comparison["events"].size();result["kernel_comparison"]=compact
        # Full histories and every serial remain in the persisted full report.
        result["gpu_analysis"]={"available":false,"groups":[],"scope":"Use paired kernel_comparison; full timestamp history saved separately."}
        result["current_mode_diagnostic"]={}
    return result
func _report_header(report: Dictionary) -> String:
    var text: String=super._report_header(report).replace("LIE 1.3","LIE 1.4")
    var comparison: Dictionary=report.get("kernel_comparison",{})
    if comparison.is_empty():return text
    text="LIE 1.4 · COMPARACIÓN GPU\n%s · %s\n" % [report["device"],report["gpu"]]
    for kind in ["camera","light_power","light_position"]:
        text+="\n"+{"camera":"Cámara","light_power":"Potencia","light_position":"Posición de luz"}[kind]
        for mode in KERNEL_MODES:
            for entry in comparison["summary"]:
                if entry["kind"]==kind and entry["mode"]==mode:text+="\n%s: %.2f ms · %d eventos" % [{"legacy":"1.2","monolithic":"1.3","split":"1.4"}[mode],entry["gpu"]["p50_ms"],entry["gpu"]["samples"]]
    return text+"\n\nMisma escena y secuencia. Tiempos GPU; FPS de pantalla y CPU se informan aparte.\n\n"
func _ui() -> void:
    super._ui();var box: Node=status.get_parent()
    _label(box,"COMPARACIÓN DE RENDIMIENTO",19)
    _kernel_picker=OptionButton.new()
    for label in ["Referencia 1.2","LIE 1.3","LIE 1.4 · kernels separados"]:_kernel_picker.add_item(label)
    _kernel_picker.select(KERNEL_MODES.find(state["kernel_mode"]));_kernel_picker.item_selected.connect(func(index: int):command({"op":"set_values","values":{"kernel_mode":KERNEL_MODES[index]}}));box.add_child(_kernel_picker)
    _button(box,"Medir solo el modo actual",func():command({"op":"diagnose"}))
    for item in picture.get_parent().get_children():
        if item is Button and item.text=="Medir modo actual":
            for connection in item.pressed.get_connections():item.pressed.disconnect(connection["callable"])
            item.text="Comparar GPU";item.pressed.connect(func():command({"op":"compare_kernels"}))
        if item is Label and item.text.begins_with("LIE ·"):item.text="LIE · Kernels independientes · 1.4.0"
func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot();result["control_contract"]["kernel_modes"]=KERNEL_MODES
    result["control_contract"]["kernel_comparison"]={"start":{"op":"compare_kernels"},"cancel":{"op":"benchmark_cancel"},"restores_state":true}
    return result
