extends SceneTree
const Policy = preload("res://lie_camera_render_policy.gd")
var checks: int = 0
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed = true; printerr("CAMERA COMMAND FAIL ", label)
func run() -> void:
	for value in [720, 810, 900, 1080, 1440]: check(Policy.valid_size(value), "explicit internal size accepted")
	for value in [720.0, 0, -1, 10000, true, "720", null]: check(not Policy.valid_size(value), "invalid internal size rejected")
	for value in ["compute", "graphics"]: check(Policy.valid_backend(value), "explicit backend accepted")
	for value in ["native", 1, true, null]: check(not Policy.valid_backend(value), "invalid backend rejected")
	var lab = load("res://lie_wall24_android_lab.tscn").instantiate(); root.add_child(lab); await process_frame
	check(lab.effect.capture_loaded and lab.state["internal_resolution"] == 1080 and lab.state["raster_backend"] == "compute", "source bank and reference defaults")
	var before: Dictionary = lab.state.duplicate(true); var revision: int = lab.revision
	for values in [{"internal_resolution": 720.0, "light_power": 2.0}, {"raster_backend": "bad", "camera_yaw": 30.0}, {"internal_resolution": null}]:
		check(not lab.command({"op": "set_values", "values": values})["ok"] and lab.state == before and lab.revision == revision, "invalid transaction atomic")
	check(lab.command({"op": "set_values", "values": {"internal_resolution": 810}})["ok"] and lab.effect.render_size == 810 and lab.effect.output_size == 720, "internal size independent of output")
	check(lab.command({"op": "set_values", "values": before})["ok"] and lab.state == before, "resolution controls roundtrip")
	check(lab.command({"op": "compare_kernels", "quick": true})["ok"], "four-mode camera comparison accepted")
	check(not lab.command({"op": "set_values", "values": {"internal_resolution": 720}})["ok"], "external edits locked during comparison")
	lab.command({"op": "benchmark_cancel"})
	for i in range(24): await process_frame
	check(not lab.benchmark_busy and lab.state == before and lab._comparison_report.get("cancelled", false) and lab._comparison_report.get("restored", false), "cancel restores exact state")
	for mode in lab.CAMERA_MODES:
		var values: Dictionary = lab._camera_mode_state(before, mode)
		check(values["stage_timestamps"] == false and values["lean_barriers"] == false and values["screen_tiles"] == false and values["power_response"], "comparison holds unrelated options fixed")
	lab.queue_free(); await process_frame
	print("CAMERA COMMAND ", checks, " ", "FAIL" if failed else "PASS"); quit(1 if failed else 0)
