extends "res://lie_wall22_tile_effect.gd"
const ResponseKernels = preload("res://lie_power_response_kernels.gd")
const ResponsePolicy = preload("res://lie_power_response_policy.gd")
var power_response: bool = true
var stage_timestamps: bool = false
var lean_barriers: bool = false
var response_builds: int = 0
var response_reuses: int = 0
var response_allocations: int = 0
var lean_transitions: int = 0
var solve_profile = PassProfile.new()
var _gpu_response: bool = true
var _gpu_stage_timestamps: bool = false
var _gpu_lean: bool = false
var _response_rid: = RID()
var _response_bytes: int = 0
var _response_shape: = Vector2i()
var _response_pipelines: Dictionary = {}
var _response_sets: Dictionary = {}
var _response_key: Dictionary = {}
var _response_lights: = PackedByteArray()
var _last_response_key: Dictionary = {}
var _last_response_lights: = PackedByteArray()
var _response_valid: bool = false
var _response_action: String = "reference"
var _next_response_key: Dictionary = {}
var _next_response_lights: = PackedByteArray()
var _response_shaded: bool = false

func set_response_options(enabled: bool, stages: bool, lean: bool) -> void :
	if power_response == enabled and stage_timestamps == stages and lean_barriers == lean: return
	power_response = enabled;stage_timestamps = stages;lean_barriers = lean
	if gpu_ready: RenderingServer.call_on_render_thread( func():
		if not gpu_ready: return
		if _gpu_response != enabled: _response_valid = false;_last_response_key = {}
		_gpu_response = enabled;_gpu_stage_timestamps = stages;_gpu_lean = lean
		_resident = PackedByteArray();_shade_dirty = true)

func invalidate_lighting() -> void :


	RenderingServer.call_on_render_thread( func():
		_resident = PackedByteArray();_shade_dirty = true)

func _reset_coded_signature() -> void :
	_response_valid = false;_last_response_key = {}
	super._reset_coded_signature()

func _initialize() -> bool:
	_gpu_response = power_response;_gpu_stage_timestamps = stage_timestamps;_gpu_lean = lean_barriers
	return super._initialize()

func _make_set() -> void :
	_free_response_sets()
	super._make_set()
	_response_valid = false;_last_response_key = {}
	if _response_rid.is_valid(): _bind_response_sets()

func _free_response_sets() -> void :
	for rid in _response_sets.values():
		if rid.is_valid() and _rd.uniform_set_is_valid(rid): _rd.free_rid(rid)
	_response_sets.clear()

func _bind_response_sets() -> bool:
	if _response_pipelines.is_empty():
		for key in ResponseKernels.SHADERS:
			var spirv: RDShaderSPIRV = ResponseKernels.SHADERS[key].get_spirv()
			if spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE) != "": return false
			var shader: RID = _rd.shader_create_from_spirv(spirv)
			var pipeline: RID = _rd.compute_pipeline_create(shader)
			_response_pipelines[key] = {"shader": shader, "pipeline": pipeline}
			if not pipeline.is_valid(): return false
	var handles: Dictionary = _buffers.duplicate();handles.merge(_images)
	handles[14] = transport.output_rid;handles[15] = transport.material_codes_rid()
	handles[23] = transport.surface_light_codes_rid();handles[34] = transport.emission_descriptors_rid();handles[42] = _response_rid
	for key in ResponseKernels.SHADERS:
		var uniforms: Array[RDUniform] = []
		for binding in ResponseKernels.BINDINGS[key]: uniforms.append(_uniform(binding, handles[binding], binding in [8, 9, 11, 12, 14]))
		var rid: RID = _rd.uniform_set_create(uniforms, _response_pipelines[key]["shader"], 0)
		_response_sets[key] = rid
		if not rid.is_valid(): return false
	return true

func _ensure_response() -> bool:
	var shape: = Vector2i(render_size, transport.desired_light_count)
	if shape.y < 1 or shape.y > 8: return false
	if _response_shape != shape:
		_free_response_sets()
		if _response_rid.is_valid(): _rd.free_rid(_response_rid);allocation_bytes -= _response_bytes
		_response_bytes = 128 + shape.x * shape.x * shape.y * 32
		_response_rid = _rd.storage_buffer_create(_response_bytes, PackedByteArray())
		if not _response_rid.is_valid(): _response_bytes = 0;return false
		allocation_bytes += _response_bytes;response_allocations += 1;_response_shape = shape;_response_valid = false
	return not _response_sets.is_empty() or _bind_response_sets()

func _render_callback(type: int, data: RenderData) -> void :
	if not capture_loaded or ( not gpu_ready and not _initialize()): return
	_mutex.lock(); var next: Dictionary = _pending.duplicate();_mutex.unlock()
	if next.is_empty() or next["parameters"].decode_s32(88) != render_size: return
	var params: PackedByteArray = next["parameters"]
	var signature: PackedByteArray = params.duplicate();signature.append_array(next["instances"]);signature.append_array(next["jobs"])
	if signature == _resident:
		super._render_callback(type, data);return
	var geometry: PackedByteArray = params.slice(0, 96)
	geometry.append_array(params.slice(152, 160));geometry.append_array(params.slice(208, 256))
	geometry.append_array(next["instances"]);geometry.append_array(next["jobs"])
	var inputs: Dictionary = transport.direct_response_inputs()
	_next_response_key = {"geometry": geometry, "transport": inputs["signature"]}
	_next_response_lights = inputs["lights"];_response_action = "reference";_response_shaded = false
	var eligible: bool = _gpu_response and query_supported and _gpu_kernel_mode == "split" and geometry == _geometry_resident and not _filter_recovery_dirty and (contact_shadows or surface_detail or material_response)
	if eligible:
		if _response_valid and _response_key == _next_response_key and ResponsePolicy.compatible(_response_lights, _next_response_lights):
			_response_action = "reuse"
		elif _last_response_key == _next_response_key and _last_response_lights != _next_response_lights and ResponsePolicy.compatible(_last_response_lights, _next_response_lights):
			if _ensure_response(): _response_action = "capture"
	var serial: int = frame_count + 1
	_rd.capture_timestamp(solve_profile.marker( - get_instance_id(), serial, "solve", "begin"))
	super._render_callback(type, data)
	if frame_count == serial:
		_rd.capture_timestamp(solve_profile.marker( - get_instance_id(), serial, "solve", "end"))
		var context: Dictionary = {"event_kind": _profile_event_kind, "internal_size": render_size, "power_response": _gpu_response, "stage_timestamps": _gpu_stage_timestamps, "lean_barriers": _gpu_lean, "tight_bounds": _gpu_tight_bounds, "timing_scope": "whole_appearance"}
		solve_profile.set_context(serial, context)
		if _response_shaded:
			_last_response_key = _next_response_key;_last_response_lights = _next_response_lights
			if _response_action == "capture":
				_response_key = _next_response_key;_response_lights = _next_response_lights;_response_valid = true;response_builds += 1
			elif _response_action == "reuse": response_reuses += 1
			else: _response_valid = false

func _stage(list: int, stage: int, count: int) -> void :
	if stage == 1: _response_valid = false;_last_response_key = {};_response_action = "reference"
	_measured_options["power_response"] = _gpu_response
	_measured_options["stage_timestamps"] = _gpu_stage_timestamps
	_measured_options["lean_barriers"] = _gpu_lean
	super._stage(list, stage, count)

func _timed_stage(list: int, stage: int, count: int, name: String) -> void :
	if stage == 10:
		_response_shaded = true
		if _response_action == "reuse":
			_response_dispatch(list, "reuse", count, "surface_response_reuse");return
	super._timed_stage(list, stage, count, name)

func _dispatch_kernel(list: int, stage: int, count: int, name: String, flags: int = 0, indirect: int = -1) -> void :
	if stage == 10 and _response_action == "capture":
		_response_dispatch(list, "capture", count, "surface_response_build");return
	super._dispatch_kernel(list, stage, count, name, flags, indirect)

func _response_dispatch(list: int, key: String, count: int, name: String) -> void :
	_pass_timestamp(name, "begin")
	_rd.compute_list_bind_compute_pipeline(list, _response_pipelines[key]["pipeline"])
	_rd.compute_list_bind_uniform_set(list, _response_sets[key], 0)
	_rd.compute_list_set_push_constant(list, PackedInt32Array([10, 2, _coverage_mode, 0]).to_byte_array(), 16)
	_rd.compute_list_dispatch(list, ceili(float(count) / 64.0), 1, 1)
	_pass_barrier(list);_pass_timestamp(name, "end")

func _pass_timestamp(name: String, edge: String) -> void :
	if _gpu_stage_timestamps or not query_supported or _gpu_kernel_mode != "split": super._pass_timestamp(name, edge)

func _pass_barrier(list: int) -> void :
	if not _gpu_lean: super._pass_barrier(list);return



	_rd.compute_list_end();_rd.compute_list_begin();lean_transitions += 1

func _collect_profile() -> void :
	super._collect_profile();solve_profile.collect(_rd, - get_instance_id())

func cache_metrics() -> Dictionary:
	var result: Dictionary = super.cache_metrics()
	result["power_response"] = {"enabled": power_response, "valid": _response_valid, "builds": response_builds, "reuses": response_reuses, "allocations": response_allocations, "requested_bytes": _response_bytes, "physical_lights": _response_shape.y, "scope": "lazy per-pixel/per-light direct detail; coarse/indirect transport recomputed unchanged; scalar power only; camera, position, material and options invalidate"}
	result["submission"] = {"stage_timestamps": stage_timestamps, "lean_barriers": lean_barriers, "lean_transitions": lean_transitions, "scope": "same dependency boundaries; omit restoration of state immediately rebound by every dispatch; whole appearance interval retained"}
	return result

func _release() -> void :
	_free_response_sets()
	for entry in _response_pipelines.values():
		for rid in [entry["pipeline"], entry["shader"]]:
			if rid.is_valid(): _rd.free_rid(rid)
	_response_pipelines.clear()
	if _response_rid.is_valid(): _rd.free_rid(_response_rid);allocation_bytes -= _response_bytes
	_response_rid = RID();_response_bytes = 0;_response_shape = Vector2i()
	_response_valid = false;_last_response_key = {}; super._release()
