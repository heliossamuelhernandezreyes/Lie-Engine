extends "res://lie_wall24_graphics_effect.gd"
## Causal ablations. Incomplete images are diagnostic evidence, not optimizations.
const Census = preload("res://lie_renderer_census_kernels.gd")
const AUDIT_MODES = ["presentation", "raster_base", "recovery", "refinement", "full", "full_stages", "production"]
var audit_mode: String = "production"
var _gpu_audit_mode: String = "production"
var _census: bool = false
var _census_buffer := RID()
var _census_pipelines: Dictionary = {}
var _census_sets: Dictionary = {}
var _audit_dispatches: Array = []
var _next_dispatches: Array = []

func set_audit_mode(mode: String, census: bool = false) -> bool:
	if mode not in AUDIT_MODES: return false
	audit_mode = mode
	if gpu_ready: RenderingServer.call_on_render_thread(func():
		_gpu_audit_mode = mode; _census = census
		if _census_buffer.is_valid(): _rd.buffer_clear(_census_buffer, 0, 128)
		_response_valid = false; _last_response_key = {}
		_geometry_resident = PackedByteArray(); _resident = PackedByteArray(); _shade_dirty = true)
	else: _gpu_audit_mode = mode; _census = census
	return true

func _free_census_sets() -> void:
	for rid in _census_sets.values():
		if rid.is_valid() and _rd.uniform_set_is_valid(rid): _rd.free_rid(rid)
	_census_sets.clear()

func _make_set() -> void:
	_free_census_sets()
	super._make_set()

func _ensure_census() -> bool:
	if not query_supported or _gpu_kernel_mode != "split": return false
	if not _census_buffer.is_valid():
		var initial := PackedByteArray(); initial.resize(128)
		_census_buffer = _rd.storage_buffer_create(128, initial); allocation_bytes += 128
	if not _census_buffer.is_valid(): return false
	if _census_pipelines.is_empty():
		for stage in Census.SHADERS:
			var spirv: RDShaderSPIRV = Census.SHADERS[stage].get_spirv()
			if spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE) != "": return false
			var shader: RID = _rd.shader_create_from_spirv(spirv)
			var pipeline: RID = _rd.compute_pipeline_create(shader)
			_census_pipelines[stage] = {"shader": shader, "pipeline": pipeline}
			if not pipeline.is_valid(): return false
	if _census_sets.is_empty():
		var handles: Dictionary = _buffers.duplicate(); handles.merge(_images)
		handles[14] = transport.output_rid; handles[15] = transport.material_codes_rid()
		handles[23] = transport.surface_light_codes_rid(); handles[25] = _tangent_lease["rid"] if _gpu_tight_bounds else _visibility_lease["nodes"]
		handles[26] = _visibility_lease["leaves"]; handles[30] = _shadow_lease["rid"]
		handles[34] = transport.emission_descriptors_rid(); handles[49] = _census_buffer
		for stage in Census.SHADERS:
			var uniforms: Array[RDUniform] = []
			for binding in Census.BINDINGS[stage]: uniforms.append(_uniform(binding, handles[binding], binding in [8, 9, 11, 12, 14]))
			var rid: RID = _rd.uniform_set_create(uniforms, _census_pipelines[stage]["shader"], 0)
			_census_sets[stage] = rid
			if not rid.is_valid(): return false
	return true

func _timed_stage(list: int, stage: int, count: int, name: String) -> void:
	# Suppress the entire fine-lighting dependency group, not just its final store.
	if stage == 10 and _gpu_audit_mode in ["presentation", "raster_base", "recovery"]: return
	super._timed_stage(list, stage, count, name)

func _dispatch_kernel(list: int, stage: int, count: int, name: String, flags: int = 0, indirect: int = -1) -> void:
	if _gpu_audit_mode == "presentation" and stage != 7: return
	if _gpu_audit_mode == "raster_base" and stage in [8, 9]: return
	if _gpu_audit_mode == "refinement" and stage in [11, 12, 13]: return
	_next_dispatches.append({"stage": stage, "name": name, "count": count, "indirect": indirect})
	if _census and Census.SHADERS.has(stage):
		if not _ensure_census(): failure = "Census pipeline initialization"; return
		_pass_timestamp(name, "begin")
		_rd.compute_list_bind_compute_pipeline(list, _census_pipelines[stage]["pipeline"])
		_rd.compute_list_bind_uniform_set(list, _census_sets[stage], 0)
		_rd.compute_list_set_push_constant(list, PackedInt32Array([stage, 2, _coverage_mode, flags]).to_byte_array(), 16)
		if indirect >= 0: _rd.compute_list_dispatch_indirect(list, _buffers[indirect], 0)
		else: _rd.compute_list_dispatch(list, maxi(1, ceili(float(count) / 64.0)), 1, 1)
		_pass_barrier(list); _pass_timestamp(name, "end"); return
	super._dispatch_kernel(list, stage, count, name, flags, indirect)

func _render_callback(type: int, data: RenderData) -> void:
	var before: int = frame_count; _next_dispatches = []
	super._render_callback(type, data)
	if frame_count != before:
		_audit_dispatches = _next_dispatches.duplicate(true)
		var context: Dictionary = {"event_kind": _profile_event_kind, "internal_size": render_size, "audit_mode": _gpu_audit_mode, "census": _census, "stage_timestamps": _gpu_stage_timestamps, "power_response": _gpu_response}
		solve_profile.set_context(frame_count, context); pass_profile.set_context(frame_count, context)

func reset_census() -> void:
	RenderingServer.call_on_render_thread(func():
		if _census_buffer.is_valid(): _rd.buffer_clear(_census_buffer, 0, 128))

func request_census() -> Dictionary:
	var result: Dictionary = {}
	RenderingServer.call_on_render_thread(func():
		if not gpu_ready or not _census_buffer.is_valid(): result["error"] = "Census unavailable"; return
		var words: PackedInt32Array = _rd.buffer_get_data(_census_buffer, 0, 128).to_int32_array()
		var counts: Dictionary = {}
		for i in range(Census.NAMES.size()): counts[Census.NAMES[i]] = int(words[i]) & 0xffffffff
		var queue: PackedByteArray = _rd.buffer_get_data(_buffers[35], 0, 16)
		var recovery: PackedByteArray = _rd.buffer_get_data(_buffers[20], 0, 16)
		var selection: PackedByteArray = _rd.buffer_get_data(_buffers[36], 0, 16)
		counts["unique_active_winners"] = queue.decode_u32(12)
		counts["selected_blocks"] = selection.decode_u32(0)
		counts["recovery_records"] = recovery.decode_u32(0); counts["recovery_overflow"] = recovery.decode_u32(4)
		result["counts"] = counts; result["serial"] = frame_count
		result["scope"] = "Logical work in a separate instrumented solve; uint32 counters, not memory transactions or production timings. Recovery neighbour reads are not instrumented." )
	return result

func _release() -> void:
	_free_census_sets()
	for entry in _census_pipelines.values():
		for rid in [entry["pipeline"], entry["shader"]]:
			if rid.is_valid(): _rd.free_rid(rid)
	_census_pipelines.clear()
	if _census_buffer.is_valid(): _rd.free_rid(_census_buffer); allocation_bytes -= 128
	_census_buffer = RID()
	super._release()
