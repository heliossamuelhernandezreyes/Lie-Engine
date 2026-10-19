extends "res://lie_wall23_android_lab.gd"
const CameraEffect = preload("res://lie_wall24_graphics_effect.gd")
const CameraPolicy = preload("res://lie_camera_render_policy.gd")
const CAMERA_MODES = {
	"reference_1080": {"internal_resolution": 1080, "raster_backend": "compute"},
	"compute_810": {"internal_resolution": 810, "raster_backend": "compute"},
	"compute_720": {"internal_resolution": 720, "raster_backend": "compute"},
	"graphics_1080": {"internal_resolution": 1080, "raster_backend": "graphics"}}
const CAMERA_LABELS = {"reference_1080": "Referencia 1080", "compute_810": "Compute 810", "compute_720": "Compute 720", "graphics_1080": "Gráficos 1080"}

func _ready() -> void:
	state["internal_resolution"] = 1080; state["raster_backend"] = "compute"
	super._ready()

func _coded_effect_factory() -> CompositorEffect: return CameraEffect.new(720)

func _apply() -> void:
	if effect != null:
		effect.set_camera_render_options(int(state.get("internal_resolution", 1080)), str(state.get("raster_backend", "compute")))
		# Explicit internal resolution supersedes the historical two-position UI.
		_last_quality = 1 if state.get("quality_2x", false) else 0
	super._apply()

func _refresh() -> void:
	# The historical selector refresh handles String-only state. Keep the
	# numeric resolution selector typed without changing previous laboratories.
	var camera_controls: Dictionary = {}
	for key in ["internal_resolution", "raster_backend"]:
		if controls.has(key): camera_controls[key] = controls[key]; controls.erase(key)
	super._refresh()
	for key in camera_controls:
		var select: OptionButton = camera_controls[key]; controls[key] = select
		for i in range(select.item_count):
			if select.get_item_text(i) == str(state[key]): select.select(i)

func command(request: Variant) -> Dictionary:
	if request is Dictionary and request.get("values", {}) is Dictionary:
		var error: String = CameraPolicy.valid_values(request.get("values", {}))
		if error != "": return {"ok": false, "error": error, "revision": revision}
	return super.command(request)

func _benchmark_set_values(values: Dictionary) -> Dictionary:
	var error: String = CameraPolicy.valid_values(values)
	if error != "": return {"ok": false, "error": error, "revision": revision}
	return super._benchmark_set_values(values)

func _stream_event(values: Dictionary, kind: String, mode: String, cycle: int, force: bool = false) -> Dictionary:
	var event: Dictionary = await super._stream_event(values, kind, mode, cycle, force)
	if effect != null:
		event["internal_size"] = effect.render_size; event["raster_backend"] = effect.raster_backend
		event["graphics_failure"] = effect.graphics_failure
		if effect.raster_backend == "graphics" and effect.graphics_failure != "": event["error"] = effect.graphics_failure
	return event

func _camera_mode_state(backup: Dictionary, mode: String) -> Dictionary:
	var values: Dictionary = backup.duplicate(true); values.merge(CAMERA_MODES[mode], true)
	values.merge({"quality_2x": false, "tight_bounds": true, "screen_tiles": false, "compact_shadows": false, "visibility_stream": false, "visibility_diagnostics": false, "kernel_mode": "split", "power_response": true, "stage_timestamps": false, "lean_barriers": false}, true)
	return values

func _camera_signature() -> Dictionary:
	var pending: Dictionary = effect.camera_raster_signature()
	for i in range(180):
		await get_tree().process_frame
		if pending.has("hashes"): return pending
	return {"error": "Raster validation readback timed out"}

func _run_comparison(quick: bool) -> void:
	hardware.release_counters(); hardware_profile = {}
	var backup: Dictionary = state.duplicate(true); var events: Array = []; var warmup: Array = []; var all_events: Array = []
	var rows: Array = []; var seen: Dictionary = {}; var stages: Array = []; var stage_seen: Dictionary = {}; var boundaries: Array = []; var error: String = ""; var skipped: Dictionary = {}
	var rounds: int = 1 if quick else 4; var modes: Array = CAMERA_MODES.keys()
	var validation: Dictionary = {"scope": "Explicit untimed preflight at the initial 1080 view; exact depth, owner and 8-channel material SHA256; precision guard; no reads during measured events"}
	for cycle in range(rounds):
		for offset in range(modes.size()):
			if _benchmark_cancelled or error != "": break
			var mode: String = modes[(cycle + offset) % modes.size()]
			if skipped.has(mode): continue
			var reset: Dictionary = _camera_mode_state(backup, mode)
			boundaries.append({"mode": mode, "cycle": cycle, "boundary": "before_block", "telemetry": hardware.telemetry()})
			var event: Dictionary = await _stream_event(reset, "initial_geometry", mode, cycle, true)
			if event.has("error"):
				if not _benchmark_cancelled and mode == "graphics_1080" and event.get("graphics_failure", "") != "":
					skipped[mode] = event["graphics_failure"]; warmup.append(event); all_events.append(event)
					boundaries.append({"mode": mode, "cycle": cycle, "boundary": "unsupported", "reason": event["graphics_failure"], "telemetry": hardware.telemetry()})
					continue
				if not _benchmark_cancelled: error = str(event["error"])
				break
			if cycle == 0 and mode in ["reference_1080", "graphics_1080"]:
				var signature: Dictionary = await _camera_signature(); validation[mode] = signature
				if signature.has("error"): error = signature["error"]; break
				if mode == "graphics_1080":
					validation["exact_match"] = signature["hashes"] == validation["reference_1080"]["hashes"] and signature["precision_guard"] == 0
					if not validation["exact_match"]:
						skipped[mode] = "Initial view fails exact depth/owner/material or float-blend precision validation"
						warmup.append(event); all_events.append(event); continue
			warmup.append(event); all_events.append(event)
			for trial in _diagnostic_trials(reset):
				if _benchmark_cancelled: break
				if _benchmark_status != null: _benchmark_status.text = "Preparando " + CAMERA_LABELS[mode]
				event = await _stream_event(trial["values"], trial["kind"], mode, cycle)
				if event.has("error"):
					if not _benchmark_cancelled: error = str(event["error"])
					break
				warmup.append(event); all_events.append(event)
			if not _benchmark_cancelled and error == "":
				for trial in _diagnostic_trials(reset):
					if _benchmark_cancelled: break
					if _benchmark_status != null: _benchmark_status.text = "Midiendo %s · %d/%d" % [CAMERA_LABELS[mode], events.size() + 1, rounds * 36]
					event = await _stream_event(trial["values"], trial["kind"], mode, cycle)
					if event.has("error"):
						if not _benchmark_cancelled: error = str(event["error"])
						break
					events.append(event); all_events.append(event)
			_comparison_collect(all_events, rows, seen); _collect_stages(all_events, stages, stage_seen)
			boundaries.append({"mode": mode, "cycle": cycle, "boundary": "after_block", "telemetry": hardware.telemetry()})
	for drain in range(8): await get_tree().process_frame
	_comparison_collect(all_events, rows, seen); _collect_stages(all_events, stages, stage_seen)
	hardware.release_counters()
	var restore: Dictionary = _benchmark_set_values(backup)
	_comparison_report = {"schema": "lie-camera-render-comparison/1", "scene": backup, "rounds": rounds, "modes": CAMERA_MODES, "skipped_modes": skipped, "events": events, "warmup_events": warmup, "warmup_summary": _stream_summary(rows, warmup), "summary": _stream_summary(rows, events), "passes": {"rows": rows}, "stage_passes": {"rows": stages}, "hardware_profile": {}, "telemetry_boundaries": boundaries, "requested_events": rounds * 36, "expected_events": rounds * (modes.size() - skipped.size()) * 9, "cancelled": _benchmark_cancelled, "error": error, "restored": restore["ok"] and state == backup, "scope": "Reference/810/720 vary internal resolution with the same 720-square output and captured bank. Graphics1080 isolates hardware footprint rasterization at identical resolution. Identical whole appearance GPU interval; fixed warm-up, cold builds and every measured event retained. Unsupported graphics mode is explicitly skipped; compute comparisons continue. No timed readbacks. Graphics is experimental. Software Vulkan is not physical Mali performance."}
	_comparison_report["raster_validation"] = validation
	_persist_report("user://lie-camera-render-last.json", _comparison_report); benchmark_busy = false
	if _benchmark_status != null: _benchmark_status.text = "Prueba cancelada; ajustes restaurados" if _benchmark_cancelled else "Comparación terminada · pulsa Informe" if error == "" else "Comparación incompleta: " + error

func _build_report() -> Dictionary:
	var result: Dictionary = super._build_report(); result["app_version"] = "2.1.0-camera-render"
	return result

func _portable_report(report: Dictionary) -> Dictionary:
	var result: Dictionary = super._portable_report(report); result["cache"]["camera_render"] = report["cache"]["camera_render"]
	if result.has("kernel_comparison"):
		result["kernel_comparison"]["modes"] = CAMERA_MODES
		result["kernel_comparison"]["skipped_modes"] = report["kernel_comparison"].get("skipped_modes", {})
		result["kernel_comparison"]["requested_events"] = report["kernel_comparison"].get("requested_events", 0)
		result["kernel_comparison"]["raster_validation"] = report["kernel_comparison"].get("raster_validation", {})
	result["copy_scope"] = "Whole appearance intervals. Full timing, warm-up, cold builds and telemetry in lie-camera-render-last.json and lie-performance-last.json."
	return result

func _report_header(report: Dictionary) -> String:
	var text: String = "LIE 2.1 · RESOLUCIÓN Y DIBUJO\n%s · %s\n" % [report["device"], report["gpu"]]
	var comparison: Dictionary = report.get("kernel_comparison", {})
	for kind in ["camera", "light_power", "light_position"]:
		text += "\n" + {"camera": "Cámara", "light_power": "Potencia", "light_position": "Posición de luz"}[kind]
		for mode in CAMERA_MODES:
			if comparison.get("skipped_modes", {}).has(mode): text += "\n%s: no disponible (%s)" % [CAMERA_LABELS[mode], comparison["skipped_modes"][mode]]
			for group in comparison.get("summary", []):
				if group["kind"] == kind and group["mode"] == mode: text += "\n%s: %.2f ms · p95 %.2f · %d eventos" % [CAMERA_LABELS[mode], group["gpu"]["p50_ms"], group["gpu"]["p95_ms"], group["gpu"]["samples"]]
	return text + "\n\nMismo tamaño de salida. Intervalo GPU completo; construcciones y picos conservados.\n\n"

func _ui() -> void:
	super._ui()
	if controls.has("quality_2x"): controls["quality_2x"].hide()
	var box: Node = status.get_parent()
	_label(box, "RESOLUCIÓN Y DIBUJO", 19)
	for pair in [["internal_resolution", "Resolución interna", CameraPolicy.INTERNAL_SIZES], ["raster_backend", "Dibujo", CameraPolicy.BACKENDS]]:
		_label(box, pair[1], 17)
		var select := OptionButton.new(); var key: String = pair[0]
		for value in pair[2]: select.add_item(str(value))
		select.item_selected.connect(func(index: int):
			var value: Variant = int(select.get_item_text(index)) if key == "internal_resolution" else select.get_item_text(index)
			command({"op": "set_values", "values": {key: value}}))
		box.add_child(select); controls[key] = select
	for item in picture.get_parent().get_children():
		if item is Label and item.text.begins_with("LIE ·"): item.text = "LIE · Resolución y dibujo · 2.1"

func agent_snapshot() -> Dictionary:
	var result: Dictionary = super.agent_snapshot()
	result["control_contract"]["internal_resolutions"] = CameraPolicy.INTERNAL_SIZES
	result["control_contract"]["raster_backends"] = CameraPolicy.BACKENDS
	result["control_contract"]["comparison_modes"] = CAMERA_MODES
	return result
