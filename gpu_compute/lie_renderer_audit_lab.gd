extends "res://lie_wall24_android_lab.gd"
const AuditEffect = preload("res://lie_renderer_audit_effect.gd")
const AUDIT_LABELS = {"presentation": "Salida residente", "raster_base": "Superficie y luz base", "recovery": "Más recuperación", "refinement": "Más luz detallada", "full": "Más visibilidad fina", "full_stages": "Completo por etapas", "production": "Producción actual"}
var _active_audit_mode: String = "production"

func _coded_effect_factory() -> CompositorEffect: return AuditEffect.new(720)

func _audit_state(backup: Dictionary, mode: String) -> Dictionary:
	var values: Dictionary = backup.duplicate(true)
	values.merge({"raster_backend": "compute", "quality_2x": false, "tight_bounds": true, "screen_tiles": false, "compact_shadows": false, "visibility_stream": false, "visibility_diagnostics": false, "kernel_mode": "split", "power_response": mode == "production", "stage_timestamps": mode == "full_stages", "lean_barriers": false, "contact_shadows": mode in ["full", "full_stages", "production"], "world_contacts": true, "surface_detail": true, "material_response": true, "surface_filter": true, "fused_shading": true, "active_visibility": true, "surface_queries": true}, true)
	return values

func _stream_event(values: Dictionary, kind: String, mode: String, cycle: int, force: bool = false) -> Dictionary:
	# Presentation must issue an output event even when the only changed value
	# would otherwise leave an identical cached signature.
	if _active_audit_mode == "presentation": effect.invalidate_lighting()
	var event: Dictionary = await super._stream_event(values, kind, mode, cycle, force)
	event["dispatches"] = effect._audit_dispatches.duplicate(true)
	return event

func _read_census() -> Dictionary:
	var pending: Dictionary = effect.request_census()
	for i in range(600):
		await get_tree().process_frame
		if pending.has("counts") or pending.has("error"): return pending
	return {"error": "Census readback timed out"}

func _measure_census(backup: Dictionary) -> Dictionary:
	_active_audit_mode = "full"; effect.set_audit_mode("full", true)
	var reset: Dictionary = _audit_state(backup, "full")
	var result: Dictionary = {"events": [], "scope": "Separate instrumented full kernels, original source disks and tangent bounds. Timings from this run are excluded from performance summaries. Logical queries are not physical memory reads."}
	var event: Dictionary = await _stream_event(reset, "cold_geometry", "census", 0, true)
	if event.has("error"): result["error"] = event["error"]; return result
	var counts: Dictionary = await _read_census(); event["work"] = counts; result["events"].append(event)
	if counts.has("error"): result["error"] = counts["error"]; return result
	for trial in _diagnostic_trials(reset):
		if _benchmark_cancelled: break
		effect.reset_census()
		event = await _stream_event(trial["values"], trial["kind"], "census", 0)
		if event.has("error"): result["error"] = event["error"]; break
		counts = await _read_census(); event["work"] = counts; result["events"].append(event)
		if counts.has("error"): result["error"] = counts["error"]; break
	return result

func _viewport_baseline() -> Dictionary:
	# Existing viewport instrumentation includes native rendering/presentation,
	# not our entire offscreen LIE interval. Never subtract this from solve time.
	var cpu: Array = []; var gpu: Array = []; var serial: int = effect.frame_count
	for i in range(30):
		if _benchmark_cancelled: break
		await get_tree().process_frame
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()))
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	return {"cpu": Diagnostics.percentiles(cpu), "gpu": Diagnostics.percentiles(gpu), "new_lie_solves": effect.frame_count - serial, "scope": "Existing native viewport with resident LIE image and no changed scene; separate timing scope, not an equivalent conventional wall or a whole-frame cost."}

func _run_comparison(quick: bool) -> void:
	hardware.release_counters(); hardware_profile = {}
	var backup: Dictionary = state.duplicate(true); var events: Array = []; var warmup: Array = []; var all_events: Array = []
	var rows: Array = []; var seen: Dictionary = {}; var stages: Array = []; var stage_seen: Dictionary = {}; var boundaries: Array = []; var error: String = ""
	var rounds: int = 1 if quick else 4; var modes: Array = AuditEffect.AUDIT_MODES
	var baseline: Dictionary = await _viewport_baseline()
	for cycle in range(rounds):
		for offset in range(modes.size()):
			if _benchmark_cancelled or error != "": break
			var mode: String = modes[(cycle + offset) % modes.size()]
			_active_audit_mode = mode; effect.set_audit_mode(mode)
			var reset: Dictionary = _audit_state(backup, mode)
			boundaries.append({"mode": mode, "cycle": cycle, "boundary": "before", "telemetry": hardware.telemetry()})
			var event: Dictionary = await _stream_event(reset, "cold_geometry", mode, cycle, true)
			if event.has("error"):
				if not _benchmark_cancelled: error = str(event["error"])
				break
			warmup.append(event); all_events.append(event)
			for measured in [false, true]:
				for trial in _diagnostic_trials(reset):
					if _benchmark_cancelled or error != "": break
					if _benchmark_status != null: _benchmark_status.text = ("Midiendo " if measured else "Preparando ") + AUDIT_LABELS[mode]
					event = await _stream_event(trial["values"], trial["kind"], mode, cycle)
					if event.has("error"):
						if not _benchmark_cancelled: error = str(event["error"])
						break
					if measured: events.append(event)
					else: warmup.append(event)
					all_events.append(event)
			_comparison_collect(all_events, rows, seen); _collect_stages(all_events, stages, stage_seen)
			boundaries.append({"mode": mode, "cycle": cycle, "boundary": "after", "telemetry": hardware.telemetry()})
	for drain in range(8): await get_tree().process_frame
	_comparison_collect(all_events, rows, seen); _collect_stages(all_events, stages, stage_seen)
	var summary: Array = _stream_summary(rows, events)
	var timed: Dictionary = {}
	for row in rows: timed[int(row["serial"])] = true
	if not _benchmark_cancelled and error == "":
		for event in events:
			if not timed.has(int(event["serial"])): error = "Missing whole GPU timestamp for serial " + str(event["serial"]); break
	var work: Dictionary = {}
	if not _benchmark_cancelled and error == "": work = await _measure_census(backup)
	if work.has("error") and error == "": error = str(work["error"])
	hardware.release_counters()
	_active_audit_mode = "production"; effect.set_audit_mode("production")
	var restore: Dictionary = _benchmark_set_values(backup)
	effect.force_geometry_rebuild()
	_comparison_report = {"schema": "lie-renderer-causal-comparison/1", "scene": backup, "rounds": rounds, "modes": modes, "mode_labels": AUDIT_LABELS, "events": events, "warmup_events": warmup, "warmup_summary": _stream_summary(rows, warmup), "summary": summary, "passes": {"rows": rows}, "stage_passes": {"rows": stages}, "work_diagnostic": work, "cached_viewport": baseline, "telemetry_boundaries": boundaries, "expected_events": rounds * modes.size() * 9, "recorded_events": events.size(), "cancelled": _benchmark_cancelled, "error": error, "restored": restore["ok"] and state == backup, "unavailable_comparisons": {"conventional_wall": "A matched conventional wall has not been implemented; cached viewport is not its substitute.", "native_vulkan_viewer": "Not implemented; no Godot versus native speedup is claimed."}, "scope": "Fixed internal/output resolution and source bank; cumulative causal ablations, not equivalent-quality speedups. All modes retain original coarse/indirect transport, reported separately. Raster-base includes material filter and coarse light; recovery adds hole reconstruction; refinement adds per-pixel direct material response with fine contacts disabled; full adds original disk visibility; full-stages repeats full with stage timestamps; production enables the existing scalar-power response cache. Presentation reruns only output from a resident internal image. Every cold setup and fixed warm-up retained. Census uses separate instrumented copies, no timed readbacks. Do not attribute costs by subtracting group medians."}
	_persist_report("user://lie-renderer-audit-last.json", _comparison_report); benchmark_busy = false
	if _benchmark_status != null: _benchmark_status.text = "Cancelado; ajustes restaurados" if _benchmark_cancelled else "Diagnóstico listo · pulsa Informe" if error == "" else "Diagnóstico incompleto: " + error

func _build_report() -> Dictionary:
	var result: Dictionary = super._build_report(); result["app_version"] = "2.2.0-causal-audit"; return result

func _portable_report(report: Dictionary) -> Dictionary:
	# Historical compactors mutate shallow summary arrays. Isolate them from
	# the full persisted causal report and construct our own comparison below.
	var result: Dictionary = super._portable_report(report.duplicate(true))
	var original: Dictionary = report.get("kernel_comparison", {})
	if not original.is_empty():
		var compact: Dictionary = original.duplicate(true)
		for key in ["events", "warmup_events", "passes", "stage_passes", "telemetry_boundaries"]: compact.erase(key)
		compact["warmup_recorded_events"] = original["warmup_events"].size()
		compact["stage_summary"] = _stream_summary(original["stage_passes"]["rows"], original["events"])
		compact["work_diagnostic"] = {"scope": original["work_diagnostic"].get("scope", ""), "events": []}
		for event in original["work_diagnostic"].get("events", []): compact["work_diagnostic"]["events"].append({"kind": event["kind"], "serial": event["serial"], "work": event["work"]})
		result["kernel_comparison"] = compact
	result["copy_scope"] = "Full causal history, per-event stages and separate work counts in lie-renderer-audit-last.json. Copied report retains all measured-group summaries and work samples."
	return result

func _report_header(report: Dictionary) -> String:
	var text: String = "LIE 2.2 · COSTE DE RECONSTRUCCIÓN\n%s · %s\n" % [report["device"], report["gpu"]]
	for kind in ["camera", "light_power", "light_position"]:
		text += "\n" + {"camera": "Cámara", "light_power": "Potencia", "light_position": "Posición de luz"}[kind]
		for group in report.get("kernel_comparison", {}).get("summary", []):
			if group["kind"] == kind: text += "\n%s: %.2f ms · p95 %.2f · %d eventos" % [AUDIT_LABELS[group["mode"]], group["gpu"]["p50_ms"], group["gpu"]["p95_ms"], group["gpu"]["samples"]]
	return text + "\n\nLas imágenes parciales son diagnóstico. Conteos de consultas medidos aparte.\n\n"

func _ui() -> void:
	super._ui()
	for item in picture.get_parent().get_children():
		if item is Label and item.text.begins_with("LIE ·"): item.text = "LIE · Reconstrucción y consultas · 2.2"

func agent_snapshot() -> Dictionary:
	var result: Dictionary = super.agent_snapshot(); result["control_contract"]["comparison_modes"] = AuditEffect.AUDIT_MODES; return result
