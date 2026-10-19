extends "res://test_lie_wall12_mobile.gd"

func raster_packets(effect: CompositorEffect) -> Dictionary:
	var result: Dictionary = {}
	RenderingServer.call_on_render_thread(func():
		for binding in [4, 5, 7]: result[str(binding)] = effect._rd.buffer_get_data(effect._buffers[binding])
		result["done"] = true)
	for i in range(180):
		await process_frame
		if result.has("done"): return result
	check(false, "raster packet readback timeout"); return {}

func same_raster(a: Dictionary, b: Dictionary, label: String) -> void:
	for binding in ["4", "5", "7"]:
		var equal: bool = a[binding] == b[binding]
		check(equal, label + " exact depth/owner/8-channel material buffer " + binding)
		if not equal:
			var av: PackedInt32Array = a[binding].to_int32_array(); var bv: PackedInt32Array = b[binding].to_int32_array()
			var n: int = 0
			for i in range(mini(av.size(), bv.size())):
				if av[i] != bv[i]:
					if n < 3: printerr("BUFFER ", binding, " index ", i, " ", av[i], " != ", bv[i])
					n += 1
			report[label + " buffer " + binding + " differences"] = n

func run() -> void:
	var old = load("res://lie_wall23_android_lab.tscn").instantiate(); root.add_child(old); await settle(16)
	check(old.effect.gpu_ready and old.transport.gpu_ready, "accepted 2.0 ready")
	if not old.effect.gpu_ready: printerr(old.effect.failure); quit(1); return
	var old_image: Dictionary = await capture(old.effect); old.queue_free(); await settle()
	var lab = load("res://lie_wall24_android_lab.tscn").instantiate(); root.add_child(lab); await settle(16)
	check(lab.effect.gpu_ready and lab.transport.gpu_ready, "actual new consumer ready")
	if not lab.effect.gpu_ready: printerr(lab.effect.failure); quit(1); return
	var reference: Dictionary = await take(lab, "reference_1080")
	save_material(reference, "camera-reference1080")
	same(old_image, reference, "compute1080 preserves accepted 2.0")
	check(reference["depth"] == old_image["depth"], "compute1080 exact original depth")
	var quality: Array = []
	for size in [810, 720, 900, 1080]:
		lab.command({"op": "set_values", "values": {"internal_resolution": size}}); await settle()
		var image: Dictionary = await take(lab, "resolution_" + str(size))
		save_material(image, "camera-resolution" + str(size))
		check(image["internal_size"] == size and image["output_size"] == 720 and lab.effect.asset_uploads == 1, "resolution resize preserves output and bank")
		quality.append({"internal_size": size, "relative_to_1080": comparison(reference["color"], image["color"]), "requested_bytes": lab.effect.allocation_bytes})
		if size == 1080: same(reference, image, "resolution roundtrip exact original output")
	for pose in [{"camera_yaw":12.}, {"camera_yaw":-71.40492919921876,"camera_elevation":3.667778227064346,"distance_factor":.6,"lighting_preset":"warm_raking","light_azimuth":-72.}, {"camera_yaw":80.}, {"internal_resolution":810,"surface_queries":false}, {"internal_resolution":720,"block_access":false}]:
		var values: Dictionary = pose.duplicate(); values["raster_backend"] = "compute"
		lab.command({"op": "set_values", "values": values}); await settle()
		var a: Dictionary = await take(lab, "compute_" + str(events.size())); var ar: Dictionary = await raster_packets(lab.effect)
		lab.command({"op": "set_values", "values": {"raster_backend": "graphics"}}); await settle()
		var b: Dictionary = await take(lab, "graphics_" + str(events.size())); var br: Dictionary = await raster_packets(lab.effect)
		check(lab.effect.graphics_failure == "" and lab.effect.graphics_builds > 0, "hardware graphics actually exercised")
		check(b.get("camera_precision_guard", -1) == 0, "integer float-blend precision domain satisfied")
		if lab.effect.graphics_failure != "": printerr(lab.effect.graphics_failure)
		same(a, b, "hardware footprint image " + str(events.size())); same_raster(ar, br, "hardware footprint " + str(events.size()))
		save_material(b, "graphics-" + str(events.size()))
	lab.command({"op": "set_values", "values": {"raster_backend":"compute","internal_resolution":1080}}); await settle()
	var backup: Dictionary = lab.state.duplicate(true)
	var quick: bool = OS.get_environment("LIE_CAMERA_QUICK") == "1"
	check(lab.command({"op":"compare_kernels","quick":quick})["ok"], "isolated camera comparison accepted")
	for i in range(30000):
		await process_frame
		if not lab.benchmark_busy: break
	var diagnostic: Dictionary = lab._comparison_report; var rounds: int = 1 if quick else 4
	check(not lab.benchmark_busy and diagnostic.get("error","missing") == "" and diagnostic.get("restored",false) and lab.state == backup, "comparison completes and restores state")
	check(diagnostic.get("events",[]).size() == rounds*36 and diagnostic.get("warmup_events",[]).size() == rounds*40 and diagnostic.get("summary",[]).size() == 12, "complete measured and warm-up histories")
	check(diagnostic.get("raster_validation", {}).get("exact_match", false), "untimed device preflight validates original raster buffers")
	for group in diagnostic.get("summary",[]): check(group["gpu"]["samples"] == rounds*3, "complete whole GPU intervals")
	var portable: Dictionary = lab._portable_report(lab._build_report())
	check(portable["app_version"] == "2.1.0-camera-render" and portable["cache"].has("camera_render"), "version and exact representation scope retained")
	check(JSON.stringify(portable).to_utf8_buffer().size() < 32768, "copied report within Android budget")
	# Exercise the unsupported-format branch with real compute rendering. The
	# driver query itself was exercised by all preceding graphics comparisons.
	var formats: Dictionary = lab.effect.graphics_format_support.duplicate(true)
	lab.effect.graphics_format_support = {"available": true, "r32_float_blend": false, "rgba32_float_blend": false}
	check(lab.command({"op":"compare_kernels","quick":true})["ok"], "unsupported graphics does not block compute comparison")
	for i in range(30000):
		await process_frame
		if not lab.benchmark_busy: break
	var fallback: Dictionary = lab._comparison_report.duplicate(true)
	check(fallback.get("error", "missing") == "" and fallback.get("skipped_modes", {}).has("graphics_1080") and fallback.get("restored", false) and lab.state == backup, "unsupported mode explicitly reported and state restored")
	check(fallback.get("events", []).size() == 27 and fallback.get("expected_events", 0) == 27 and fallback.get("summary", []).size() == 9, "all three compute modes still measured")
	lab.effect.graphics_format_support = formats
	var frames: int = lab.effect.frame_count; await settle(12)
	check(lab.effect.frame_count == frames and lab.effect.asset_uploads == 1 and lab.agent_snapshot()["collider_count"] == 1 and lab.agent_snapshot()["metrics"]["visible_source_meshes"] == 0, "idle image reuse, one bank and one invisible collider")
	report.merge({"checks": checks, "failed": failed, "device": lab.effect._rd.get_device_name(), "quality": quality, "events": events, "comparison": diagnostic, "unsupported_format_comparison": fallback, "cache": lab.effect.cache_metrics(), "physical_android_tested": false})
	var file := FileAccess.open("res://wall24-native.json", FileAccess.WRITE); file.store_string(JSON.stringify(report,"  ",true,true)); file.close()
	lab.queue_free(); await settle(); print("WALL24 ", checks, " ", "FAIL" if failed else "PASS"); quit(1 if failed else 0)
