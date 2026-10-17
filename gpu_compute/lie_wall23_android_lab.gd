extends "res://lie_wall22_android_lab.gd"
const ResponseEffect = preload("res://lie_wall23_response_effect.gd")
const RESPONSE_MODES = {
	"reference": {"power_response": false, "stage_timestamps": true, "lean_barriers": false}, 
	"response": {"power_response": true, "stage_timestamps": true, "lean_barriers": false}, 
	"whole": {"power_response": true, "stage_timestamps": false, "lean_barriers": false}, 
	"lean": {"power_response": true, "stage_timestamps": false, "lean_barriers": true}}
const RESPONSE_LABELS = {"reference": "Referencia", "response": "Respuesta", "whole": "Medición global", "lean": "Envío ligero"}
func _ready() -> void :
	state["power_response"] = true;state["stage_timestamps"] = false;state["lean_barriers"] = false
	super._ready()
	_benchmark_set_values({"tight_bounds": true})
func _coded_effect_factory() -> CompositorEffect: return ResponseEffect.new(720)
func _apply() -> void :
	if effect != null: effect.set_response_options(bool(state.get("power_response", true)), bool(state.get("stage_timestamps", false)), bool(state.get("lean_barriers", false)))
	super._apply()
func command(request: Variant) -> Dictionary:
	if request is Dictionary and request.get("values", {}) is Dictionary:
		for key in ["power_response", "stage_timestamps", "lean_barriers"]:
			if request.get("values", {}).has(key) and not request["values"][key] is bool: return {"ok": false, "error": key + "_type", "revision": revision}
	return super.command(request)
func _response_mode_state(backup: Dictionary, mode: String) -> Dictionary:
	var result: Dictionary = backup.duplicate(true);result.merge(RESPONSE_MODES[mode], true)
	result.merge({"tight_bounds": true, "screen_tiles": false, "compact_shadows": false, "visibility_stream": false, "visibility_diagnostics": false, "kernel_mode": "split"}, true)
	return result
func _stream_event(values: Dictionary, kind: String, mode: String, cycle: int, force: bool = false) -> Dictionary:
	var event: Dictionary = await super._stream_event(values, kind, mode, cycle, force)
	event["response_builds"] = effect.response_builds;event["response_reuses"] = effect.response_reuses
	event["response_action"] = effect._response_action
	return event
func _comparison_collect(events: Array, rows: Array, seen: Dictionary) -> void :
	var selected: Dictionary = {}
	for event in events:
		if event.has("serial"): selected[int(event["serial"])] = true
	for row in effect.solve_profile.snapshot().get("rows", []):
		var key: String = str(row["serial"]) + "|" + row["pass"]
		if selected.has(int(row["serial"])) and not seen.has(key): rows.append(row);seen[key] = true
func _collect_stages(events: Array, rows: Array, seen: Dictionary) -> void :
	var selected: Dictionary = {}
	for event in events:
		if event.has("serial"): selected[int(event["serial"])] = true
	for row in effect.pass_profile.snapshot().get("rows", []):
		var key: String = str(row["serial"]) + "|" + row["pass"]
		if selected.has(int(row["serial"])) and not seen.has(key): rows.append(row);seen[key] = true
func _run_comparison(quick: bool) -> void :
	hardware.release_counters();hardware_profile = {}
	var backup: Dictionary = state.duplicate(true); var events: Array = []; var warmup: Array = []; var all_events: Array = []
	var rows: Array = []; var seen: Dictionary = {}; var stages: Array = []; var stage_seen: Dictionary = {}; var boundaries: Array = []; var error: String = ""
	var rounds: int = 1 if quick else 4; var modes: Array = RESPONSE_MODES.keys()
	for cycle in range(rounds):
		for offset in range(modes.size()):
			if _benchmark_cancelled or error != "": break
			var mode: String = modes[(cycle + offset) % modes.size()]
			var reset: Dictionary = _response_mode_state(backup, mode)
			boundaries.append({"mode": mode, "cycle": cycle, "boundary": "before_block", "telemetry": hardware.telemetry()})
			var event: Dictionary = await _stream_event(reset, "initial_geometry", mode, cycle, true)
			if event.has("error"):
				if not _benchmark_cancelled: error = event["error"]
				break
			warmup.append(event);all_events.append(event)
			for trial in _diagnostic_trials(reset):
				if _benchmark_cancelled: break
				if _benchmark_status != null: _benchmark_status.text = "Preparando " + RESPONSE_LABELS[mode]
				event = await _stream_event(trial["values"], trial["kind"], mode, cycle)
				if event.has("error"):
					if not _benchmark_cancelled: error = event["error"]
					break
				warmup.append(event);all_events.append(event)
			if not _benchmark_cancelled and error == "":
				for trial in _diagnostic_trials(reset):
					if _benchmark_cancelled: break
					if _benchmark_status != null: _benchmark_status.text = "Midiendo %s · %d/%d" % [RESPONSE_LABELS[mode], events.size() + 1, rounds * 36]
					event = await _stream_event(trial["values"], trial["kind"], mode, cycle)
					if event.has("error"):
						if not _benchmark_cancelled: error = event["error"]
						break
					events.append(event);all_events.append(event)
			_comparison_collect(all_events, rows, seen);_collect_stages(all_events, stages, stage_seen)
			boundaries.append({"mode": mode, "cycle": cycle, "boundary": "after_block", "telemetry": hardware.telemetry()})
	for drain in range(8): await get_tree().process_frame
	_comparison_collect(all_events, rows, seen);_collect_stages(all_events, stages, stage_seen)
	var summary: Array = _stream_summary(rows, events); var warmup_summary: Array = _stream_summary(rows, warmup)
	if not _benchmark_cancelled and error == "": hardware_profile = await _measure_hardware(backup)
	hardware.release_counters()
	var restore: Dictionary = _benchmark_set_values(backup)
	_comparison_report = {"schema": "lie-power-response-comparison/1", "scene": backup, "rounds": rounds, "modes": RESPONSE_MODES, "events": events, "warmup_events": warmup, "warmup_summary": warmup_summary, "summary": summary, "passes": {"rows": rows}, "stage_passes": {"rows": stages}, "hardware_profile": hardware_profile, "telemetry_boundaries": boundaries, "expected_events": rounds * 36, "cancelled": _benchmark_cancelled, "error": error, "restored": restore["ok"] and state == backup, "scope": "Same scene and tight bounds in all four modes. Reference -> direct response -> whole-only timestamps -> lean state transitions. Identical outer GPU interval in all modes; stage deltas retained separately, never added to whole time. Four rotated rounds, fixed separate warm-up and every cold response build retained. Camera and source-position changes use original surface shader without response writes. Indirect transport stays original. No timed GPU buffer/image reads; thermal/frequency uncontrolled."}
	_persist_report("user://lie-power-response-last.json", _comparison_report);benchmark_busy = false
	if _benchmark_status != null: _benchmark_status.text = "Comparación cancelada; ajustes restaurados" if _benchmark_cancelled else "Comparación terminada · pulsa Informe" if error == "" else "Comparación incompleta: " + error
func _hardware_modes() -> Dictionary:
	return {"reference": _response_mode_state(state, "reference"), "lean": _response_mode_state(state, "lean")}
func _build_report() -> Dictionary:
	var result: Dictionary = super._build_report();result["app_version"] = "2.0.0-power-response"
	result["whole_appearance"] = effect.solve_profile.snapshot()
	result["gpu_analysis"] = Diagnostics.summarize(result["whole_appearance"])
	result["scope"] = "Whole appearance GPU intervals include changed-image work and inter-stage gaps; transport remains separately reported. Stage timings are separate. Display FPS includes cached images. Requested bytes are not measured VRAM/PSS."
	return result
func _portable_report(report: Dictionary) -> Dictionary:
	var result: Dictionary = super._portable_report(report)
	for key in ["power_response", "submission"]: result["cache"][key] = report["cache"][key]
	result["whole_appearance"] = {"scope": report["whole_appearance"]["scope"], "passes": report["whole_appearance"]["passes"]}
	var comparison: Dictionary = result.get("kernel_comparison", {})
	if not comparison.is_empty():
		comparison["modes"] = RESPONSE_MODES
		comparison["response_events"] = []
		for event in report["kernel_comparison"].get("events", []):
			if event.get("kind") == "light_power": comparison["response_events"].append({"mode": event["mode"], "cycle": event["cycle"], "serial": event["serial"], "action": event["response_action"]})
	result["copy_scope"] = "Whole-interval comparison; full events, cold builds, warm-up, per-stage timing and telemetry in lie-power-response-last.json and lie-performance-last.json"
	return result
func _report_header(report: Dictionary) -> String:
	var comparison: Dictionary = report.get("kernel_comparison", {})
	if comparison.is_empty(): return "LIE 2.0 · RESPUESTA Y ENVÍO\n%s · %s\n%s\n\n" % [report["device"], report["gpu"], Diagnostics.brief(report["gpu_analysis"])]
	var text: String = "LIE 2.0 · RESPUESTA Y ENVÍO\n%s · %s\n" % [report["device"], report["gpu"]]
	for kind in ["camera", "light_power", "light_position"]:
		text += "\n" + {"camera": "Cámara", "light_power": "Potencia", "light_position": "Posición de luz"}[kind]
		for mode in RESPONSE_MODES:
			for group in comparison["summary"]:
				if group["kind"] == kind and group["mode"] == mode: text += "\n%s: %.2f ms · %d eventos" % [RESPONSE_LABELS[mode], group["gpu"]["p50_ms"], group["gpu"]["samples"]]
	return text + "\n\nIntervalo GPU completo en todos los modos. Construcciones de caché y picos conservados.\n\n"
func _ui() -> void :
	super._ui(); var box: Node = status.get_parent()
	_check(box, "power_response", "Reutilizar detalle al cambiar potencia")
	_check(box, "stage_timestamps", "Medir cada etapa del diagnóstico")
	_check(box, "lean_barriers", "Envío ligero a GPU")
	for item in picture.get_parent().get_children():
		if item is Label and item.text.begins_with("LIE ·"): item.text = "LIE · Respuesta y envío · 2.0"
func agent_snapshot() -> Dictionary:
	var result: Dictionary = super.agent_snapshot()
	for key in ["power_response", "stage_timestamps", "lean_barriers"]: result["control_contract"]["booleans"].append(key)
	result["control_contract"]["comparison_modes"] = RESPONSE_MODES
	return result
