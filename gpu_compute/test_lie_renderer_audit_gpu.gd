extends "res://test_lie_wall24_mobile.gd"

func census(lab: Node) -> Dictionary:
	var result: Dictionary = await lab._read_census()
	check(result.has("counts") and not result.has("error"), "actual census readback")
	return result.get("counts", {})

func clear_tail(effect: CompositorEffect, count_override: int = 0) -> Dictionary:
	var result: Dictionary = {}
	var scheduled_count: int = count_override
	if scheduled_count == 0:
		for dispatch in effect._audit_dispatches:
			if dispatch["stage"] == 1: scheduled_count = dispatch["count"]
	if scheduled_count == 0: return {"error": "No production clear dispatch recorded"}
	RenderingServer.call_on_render_thread(func():
		var work: int = effect._source_work
		var dirty := PackedByteArray(); dirty.resize(work * 8)
		for i in range(work): dirty.encode_u32(i * 8 + 4, 0x80000000)
		effect._rd.buffer_update(effect._buffers[28], 0, dirty.size(), dirty)
		var list: int = effect._rd.compute_list_begin()
		# Exercise the count actually supplied by the production render callback.
		effect._dispatch_kernel(list, 1, scheduled_count, "clear_test")
		effect._rd.compute_list_end()
		var after: PackedByteArray = effect._rd.buffer_get_data(effect._buffers[28], 0, dirty.size())
		var stale: int = 0
		for i in range(work):
			if after.decode_u32(i * 8 + 4) != 0: stale += 1
		result["stale"] = stale; result["source_work"] = work)
	for i in range(600):
		await process_frame
		if result.has("stale"): return result
	return {"error": "clear readback timeout"}

func run() -> void:
	var old = load("res://lie_wall24_android_lab.tscn").instantiate(); root.add_child(old); await settle(16)
	check(old.effect.gpu_ready and old.transport.gpu_ready, "reference ready")
	if not old.effect.gpu_ready: printerr(old.effect.failure); quit(1); return
	var reference: Dictionary = await capture(old.effect); old.queue_free(); await settle()
	var lab = load("res://lie_renderer_audit_lab.tscn").instantiate(); root.add_child(lab); await settle(16)
	check(lab.effect.gpu_ready and lab.transport.gpu_ready, "audit ready")
	if not lab.effect.gpu_ready: printerr(lab.effect.failure); quit(1); return
	var actual: Dictionary = await capture(lab.effect)
	same(reference, actual, "production path preserves original image")
	var backup: Dictionary = lab.state.duplicate(true)
	var values: Dictionary = lab._audit_state(backup, "full")
	lab.effect.set_audit_mode("full"); lab.command({"op": "set_values", "values": values}); lab.effect.prepare_stream_comparison(); await settle()
	var plain: Dictionary = await capture(lab.effect); var packets: Dictionary = await raster_packets(lab.effect)
	lab.effect.set_audit_mode("full", true); lab.effect.prepare_stream_comparison(); await settle()
	var instrumented: Dictionary = await capture(lab.effect)
	same(plain, instrumented, "census preserves original output")
	same_raster(packets, await raster_packets(lab.effect), "census preserves original raster")
	var counts: Dictionary = await census(lab)
	check(counts.get("selected_sample_invocations", 0) > 0 and counts.get("material_contributions", 0) > 0 and counts.get("base_node_evaluations", 0) > 0, "geometry and interpolation actually counted")
	check(counts.get("local_light_evaluations", 0) > 0 and counts.get("full_shadow_traversals", 0) > 0 and counts.get("disk_tests", 0) > 0, "direct evaluation and original disk traversal counted")
	check(counts.get("shadow_cache_hits", 0) + counts.get("full_shadow_traversals", 0) <= counts.get("source_light_pairs", 0), "cache and trace counts consistent")
	lab.effect.set_audit_mode("production")
	for size in [1080, 720, 720]:
		lab.command({"op": "set_values", "values": {"internal_resolution": size, "camera_yaw": 10.0 + size * .001}}); lab.effect.force_geometry_rebuild(); await settle()
		if size == 720:
			var negative: Dictionary = await clear_tail(lab.effect, 720 * 720)
			check(negative.get("stale", -1) == 17270, "original dispatch reproduces 17270 stale tail flags")
		var cleared: Dictionary = await clear_tail(lab.effect)
		check(cleared.get("source_work", 0) == 535670 and cleared.get("stale", -1) == 0, "clear covers every source slot at " + str(size))
		lab.effect.force_geometry_rebuild(); await settle()
		lab.command({"op": "set_values", "values": {"light_azimuth": 30.0 + size * .001}}); await settle()
		var cached: Dictionary = await capture(lab.effect)
		lab.effect.prepare_stream_comparison(); await settle()
		same(cached, await capture(lab.effect), "light result equals fresh visibility after resize " + str(size))
	lab.command({"op": "set_values", "values": backup}); await settle()
	check(lab.command({"op": "compare_kernels", "quick": true})["ok"], "causal comparison accepted")
	for i in range(50000):
		await process_frame
		if not lab.benchmark_busy: break
	var diagnostic: Dictionary = lab._comparison_report
	check(not lab.benchmark_busy and diagnostic.get("error", "missing") == "" and diagnostic.get("restored", false) and lab.state == backup, "complete comparison and restore")
	if diagnostic.get("error", "") != "": printerr(diagnostic.get("error"))
	check(diagnostic.get("events", []).size() == 63 and diagnostic.get("warmup_events", []).size() == 70 and diagnostic.get("summary", []).size() == 21, "seven cases, same changes, complete histories")
	for group in diagnostic.get("summary", []): check(group["gpu"]["samples"] == 3, "all outer timestamps retained")
	for event in diagnostic.get("events", []):
		var ids: Array = []
		for dispatch in event["dispatches"]: ids.append(dispatch["stage"])
		if event["mode"] == "presentation": check(ids == [7], "presentation issues only output")
		if event["mode"] == "raster_base": check(8 not in ids and 9 not in ids and 10 not in ids and 11 not in ids, "base excludes recovery and all fine lighting")
		if event["mode"] == "recovery": check(10 not in ids and 11 not in ids, "recovery excludes all fine lighting")
		if event["mode"] == "refinement": check(10 in ids and 11 not in ids and 12 not in ids and 13 not in ids, "refinement excludes fine visibility dependency group")
	check(diagnostic.get("work_diagnostic", {}).get("events", []).size() == 10, "cold and nine separate instrumented events")
	var portable: Dictionary = lab._portable_report(lab._build_report())
	check(portable["kernel_comparison"].has("stage_summary") and portable["kernel_comparison"].has("unavailable_comparisons"), "stage attribution and missing baselines explicit")
	check(JSON.stringify(portable).to_utf8_buffer().size() < 196608, "copy report fits clipboard limit")
	report.merge({"checks": checks, "failed": failed, "counts": counts, "comparison": diagnostic, "physical_android_tested": false})
	var file := FileAccess.open("res://renderer-audit-native.json", FileAccess.WRITE); file.store_string(JSON.stringify(report, "  ", true, true)); file.close()
	lab.queue_free(); await settle(); print("RENDERER AUDIT ", checks, " ", "FAIL" if failed else "PASS"); quit(1 if failed else 0)
