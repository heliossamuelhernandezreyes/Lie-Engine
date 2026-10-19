extends SceneTree
var checks: int = 0
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed = true; printerr("AUDIT COMMAND FAIL ", label)
func run() -> void:
	var lab = load("res://lie_renderer_audit_lab.tscn").instantiate(); root.add_child(lab); await process_frame
	check(lab.effect.capture_loaded, "verified original bank")
	var backup: Dictionary = lab.state.duplicate(true)
	for mode in lab.AuditEffect.AUDIT_MODES:
		var values: Dictionary = lab._audit_state(backup, mode)
		check(values["internal_resolution"] == backup["internal_resolution"] and values["raster_backend"] == "compute", "same resolution; supported compute path")
		check(values["power_response"] == (mode == "production") and values["stage_timestamps"] == (mode == "full_stages"), "timing and cache controls explicit")
		check(values["contact_shadows"] == (mode in ["full", "full_stages", "production"]), "fine contact ablation declared")
	check(not lab.effect.set_audit_mode("unknown"), "unknown private mode rejected")
	check(lab.command({"op": "compare_kernels", "quick": true})["ok"], "existing comparison command")
	check(not lab.command({"op": "set_values", "values": {"light_power": 2.0}})["ok"], "external changes locked")
	lab.command({"op": "benchmark_cancel"})
	for i in range(60): await process_frame
	check(not lab.benchmark_busy and lab.state == backup and lab._comparison_report.get("cancelled", false) and lab._comparison_report.get("restored", false), "cancellation restores exact state")
	lab.queue_free(); await process_frame
	print("AUDIT COMMAND ", checks, " ", "FAIL" if failed else "PASS"); quit(1 if failed else 0)
