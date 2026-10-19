extends "res://lie_wall23_response_effect.gd"
## Experimental hardware MIN/ADD footprints; original source/lighting ABI.
const GraphicsKernels = preload("res://lie_graphics_splat_kernels.gd")
const CameraPolicy = preload("res://lie_camera_render_policy.gd")
var raster_backend: String = "compute"
var _gpu_raster_backend: String = "compute"
var _graphics_images: Dictionary = {}
var _graphics_frames: Dictionary = {}
var _graphics_pipelines: Dictionary = {}
var _graphics_sets: Dictionary = {}
var _graphics_sampler := RID()
var _graphics_args := RID()
var _graphics_size: int = 0
var _graphics_flags: int = 0
var _graphics_frame_active: bool = false
var graphics_builds: int = 0
var graphics_allocations: int = 0
var graphics_failure: String = ""
var graphics_format_support: Dictionary = {}

func set_camera_render_options(size: int, backend: String) -> void:
	if not CameraPolicy.valid_size(size) or not CameraPolicy.valid_backend(backend): return
	var resized: bool = render_size != size
	var changed: bool = raster_backend != backend
	if not resized and not changed: return
	raster_backend = backend
	_requested_internal = size
	render_size = size
	if gpu_ready: RenderingServer.call_on_render_thread(func():
		if not gpu_ready: return
		_gpu_raster_backend = backend
		if resized:
			_free_graphics_images()
			_resize_geometry(size)
		_geometry_resident = PackedByteArray(); _resident = PackedByteArray(); _shade_dirty = true
		_response_valid = false; _last_response_key = {})

func _initialize() -> bool:
	_gpu_raster_backend = raster_backend
	return super._initialize()

func _render_callback(type: int, data: RenderData) -> void:
	var before: int = frame_count
	super._render_callback(type, data)
	if frame_count != before:
		solve_profile.set_context(frame_count, {"event_kind": _profile_event_kind, "internal_size": render_size, "raster_backend": _gpu_raster_backend, "power_response": _gpu_response, "stage_timestamps": _gpu_stage_timestamps, "lean_barriers": _gpu_lean, "tight_bounds": _gpu_tight_bounds, "timing_scope": "whole_appearance"})

func _free_graphics_sets() -> void:
	for rid in _graphics_sets.values():
		if rid.is_valid() and _rd.uniform_set_is_valid(rid): _rd.free_rid(rid)
	_graphics_sets.clear()

func _free_graphics_pipelines() -> void:
	_free_graphics_sets()
	for entry in _graphics_pipelines.values():
		for rid in [entry["pipeline"], entry["shader"]]:
			if rid.is_valid(): _rd.free_rid(rid)
	_graphics_pipelines.clear()

func _graphics_pipeline_failure(message: String) -> bool:
	graphics_failure = message
	_free_graphics_pipelines()
	return false

func _free_graphics_images() -> void:
	_free_graphics_sets()
	for rid in _graphics_frames.values():
		if rid.is_valid() and _rd.framebuffer_is_valid(rid): _rd.free_rid(rid)
	_graphics_frames.clear()
	for key in _graphics_images:
		if _graphics_images[key].is_valid(): _rd.free_rid(_graphics_images[key])
		allocation_bytes -= _graphics_size * _graphics_size * (4 if key == 45 else 16)
	_graphics_images.clear(); _graphics_size = 0

func _make_set() -> void:
	_free_graphics_sets()
	super._make_set()

func _graphics_uniform(binding: int, handles: Dictionary) -> RDUniform:
	if binding not in [45, 46, 47]: return _uniform(binding, handles[binding])
	var u := RDUniform.new(); u.binding = binding
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.add_id(_graphics_sampler); u.add_id(_graphics_images[binding]); return u

func _ensure_graphics() -> bool:
	if not query_supported or _gpu_kernel_mode != "split":
		graphics_failure = "Graphics path requires the accepted split-kernel ABI"; return false
	if graphics_format_support.is_empty():
		if RenderingServer.get_current_rendering_driver_name() != "vulkan" or not ClassDB.class_exists("LieGPUProbe"):
			graphics_failure = "Vulkan format-capability module unavailable"; return false
		var probe: Object = ClassDB.instantiate("LieGPUProbe")
		if not probe.has_method("vulkan_format_support"):
			graphics_failure = "Updated Vulkan format-capability module required"; return false
		var instance: int = _rd.get_driver_resource(RenderingDevice.DRIVER_RESOURCE_TOPMOST_OBJECT, RID(), 0)
		var physical: int = _rd.get_driver_resource(RenderingDevice.DRIVER_RESOURCE_PHYSICAL_DEVICE, RID(), 0)
		graphics_format_support = probe.vulkan_format_support(instance, physical)
	if not graphics_format_support.get("available", false) or not graphics_format_support.get("r32_float_blend", false) or not graphics_format_support.get("rgba32_float_blend", false):
		graphics_failure = "GPU does not expose required float32 attachment blending"; return false
	if _graphics_size != render_size:
		_free_graphics_images()
		_graphics_size = render_size
		var usage: int = RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		for binding in [45, 46, 47]:
			var fmt := RDTextureFormat.new(); fmt.width = render_size; fmt.height = render_size
			fmt.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT if binding == 45 else RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
			fmt.usage_bits = usage
			if not _rd.texture_is_format_supported_for_usage(fmt.format, usage):
				graphics_failure = "Required float32 attachment format unavailable"; _free_graphics_images(); return false
			var rid: RID = _rd.texture_create(fmt, RDTextureView.new(), [])
			if not rid.is_valid(): graphics_failure = "Graphics attachment allocation"; _free_graphics_images(); return false
			_graphics_images[binding] = rid
			allocation_bytes += render_size * render_size * (4 if binding == 45 else 16)
		graphics_allocations += 1
		_graphics_frames["depth"] = _rd.framebuffer_create([_graphics_images[45]])
		_graphics_frames["material"] = _rd.framebuffer_create([_graphics_images[46], _graphics_images[47]])
		for rid in _graphics_frames.values():
			if not _rd.framebuffer_is_valid(rid): graphics_failure = "Graphics framebuffer"; _free_graphics_images(); return false
	if not _graphics_sampler.is_valid():
		var sampler := RDSamplerState.new()
		sampler.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST; sampler.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		_graphics_sampler = _rd.sampler_create(sampler)
		if not _graphics_sampler.is_valid(): graphics_failure = "Graphics sampler allocation"; return false
	if not _graphics_args.is_valid():
		_graphics_args = _rd.storage_buffer_create(32, PackedByteArray(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
		if not _graphics_args.is_valid(): graphics_failure = "Graphics indirect-buffer allocation"; return false
		allocation_bytes += 32
	if _graphics_pipelines.is_empty():
		for key in GraphicsKernels.SHADERS:
			var spirv: RDShaderSPIRV = GraphicsKernels.SHADERS[key].get_spirv()
			for stage in [RenderingDevice.SHADER_STAGE_COMPUTE, RenderingDevice.SHADER_STAGE_VERTEX, RenderingDevice.SHADER_STAGE_FRAGMENT]:
				if spirv.get_stage_compile_error(stage) != "": return _graphics_pipeline_failure(spirv.get_stage_compile_error(stage))
			var shader: RID = _rd.shader_create_from_spirv(spirv)
			if not shader.is_valid(): return _graphics_pipeline_failure("Graphics shader " + key)
			var pipeline: RID
			if key in ["depth", "material"]:
				var raster := RDPipelineRasterizationState.new(); raster.cull_mode = RenderingDevice.POLYGON_CULL_DISABLED
				var blend := RDPipelineColorBlendState.new()
				var attachments: Array[RDPipelineColorBlendStateAttachment] = []
				for n in range(1 if key == "depth" else 2):
					var a := RDPipelineColorBlendStateAttachment.new(); a.enable_blend = true
					a.src_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE; a.dst_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
					a.src_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE; a.dst_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
					a.color_blend_op = RenderingDevice.BLEND_OP_MINIMUM if key == "depth" else RenderingDevice.BLEND_OP_ADD
					a.alpha_blend_op = a.color_blend_op; attachments.append(a)
				blend.attachments = attachments
				pipeline = _rd.render_pipeline_create(shader, _rd.framebuffer_get_format(_graphics_frames[key]), -1, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, raster, RDPipelineMultisampleState.new(), RDPipelineDepthStencilState.new(), blend)
			else: pipeline = _rd.compute_pipeline_create(shader)
			_graphics_pipelines[key] = {"shader": shader, "pipeline": pipeline}
			if not pipeline.is_valid(): return _graphics_pipeline_failure("Float32 graphics blend pipeline " + key)
	if _graphics_sets.is_empty():
		var handles: Dictionary = _buffers.duplicate(); handles[48] = _graphics_args
		for key in GraphicsKernels.SHADERS:
			var uniforms: Array[RDUniform] = []
			for binding in GraphicsKernels.BINDINGS[key]: uniforms.append(_graphics_uniform(binding, handles))
			var rid: RID = _rd.uniform_set_create(uniforms, _graphics_pipelines[key]["shader"], 0)
			_graphics_sets[key] = rid
			if not rid.is_valid(): return _graphics_pipeline_failure("Graphics descriptor set " + key)
	graphics_failure = ""; return true

func _graphics_compute(list: int, key: String, count: int, flags: int, indirect: int = -1) -> void:
	_rd.compute_list_bind_compute_pipeline(list, _graphics_pipelines[key]["pipeline"])
	_rd.compute_list_bind_uniform_set(list, _graphics_sets[key], 0)
	_rd.compute_list_set_push_constant(list, PackedInt32Array([count, 2, _coverage_mode, flags]).to_byte_array(), 16)
	if indirect >= 0: _rd.compute_list_dispatch_indirect(list, _buffers[indirect], 0)
	else: _rd.compute_list_dispatch(list, 1 if key == "args" else maxi(1, ceili(float(count) / 64.0)), 1, 1)
	_rd.compute_list_add_barrier(list)

func _graphics_draw(key: String, flags: int) -> void:
	var colors: PackedColorArray = [Color(3.402823466e38, 0, 0, 0)] if key == "depth" else [Color(0, 0, 0, 0), Color(0, 0, 0, 0)]
	var draw: int = _rd.draw_list_begin(_graphics_frames[key], RenderingDevice.DRAW_CLEAR_COLOR_ALL, colors)
	_rd.draw_list_bind_render_pipeline(draw, _graphics_pipelines[key]["pipeline"])
	_rd.draw_list_bind_uniform_set(draw, _graphics_sets[key], 0)
	_rd.draw_list_set_push_constant(draw, PackedInt32Array([0, 2, _coverage_mode, flags]).to_byte_array(), 16)
	_rd.draw_list_draw_indirect(draw, false, _graphics_args); _rd.draw_list_end()

func _dispatch_kernel(list: int, stage: int, count: int, name: String, flags: int = 0, indirect: int = -1) -> void:
	if stage == 2: _graphics_frame_active = _gpu_raster_backend == "graphics" and _ensure_graphics()
	if stage not in [2, 3] or not _graphics_frame_active:
		super._dispatch_kernel(list, stage, count, name, flags, indirect); return
	_pass_timestamp("graphics_" + name, "begin")
	if stage == 2:
		_graphics_flags = flags
		_graphics_compute(list, "project", count, flags, indirect)
		_graphics_compute(list, "args", count, flags)
	else:
		_rd.compute_list_end()
		_graphics_draw("depth", _graphics_flags); _graphics_draw("material", _graphics_flags)
		var resumed: int = _rd.compute_list_begin()
		_graphics_compute(resumed, "resolve", render_size * render_size, flags)
		graphics_builds += 1
	_pass_timestamp("graphics_" + name, "end")

func _stage(list: int, stage: int, count: int) -> void:
	_measured_options["raster_backend"] = _gpu_raster_backend
	super._stage(list, stage, count)

func cache_metrics() -> Dictionary:
	var result: Dictionary = super.cache_metrics()
	result["camera_render"] = {"requested_backend": raster_backend, "effective_backend": "compute_fallback" if _gpu_raster_backend == "graphics" and graphics_failure != "" else _gpu_raster_backend, "failure": graphics_failure, "graphics_builds": graphics_builds, "graphics_allocations": graphics_allocations, "graphics_requested_bytes": _graphics_size * _graphics_size * 36 + (32 if _graphics_args.is_valid() else 0), "internal_size": render_size, "output_size": output_size, "scope": "original opaque disk coverage and source IDs; two auxiliary triangles per captured footprint; hardware float32 MIN/ADD; owner/visibility atomics retained; integer blend equivalence requires sums below 2^24; GPU precision guard read only during explicit diagnostics; experimental"}
	result["camera_render"]["format_support"] = graphics_format_support.duplicate(true)
	return result

func _capture() -> void:
	super._capture()
	if _graphics_args.is_valid():
		var header: PackedInt32Array = _rd.buffer_get_data(_graphics_args, 0, 32).to_int32_array()
		_mutex.lock(); _readback["camera_precision_guard"] = header[4]; _mutex.unlock()

func camera_raster_signature() -> Dictionary:
	# Explicit benchmark preflight only. Hash one buffer at a time instead of
	# retaining two complete CPU copies of the 8-channel material accumulation.
	var result: Dictionary = {}
	RenderingServer.call_on_render_thread(func():
		var hashes: Dictionary = {}
		for binding in [4, 5, 7]:
			var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256)
			hash.update(_rd.buffer_get_data(_buffers[binding])); hashes[str(binding)] = hash.finish().hex_encode()
		var guard: int = 0
		if _gpu_raster_backend == "graphics" and _graphics_args.is_valid(): guard = _rd.buffer_get_data(_graphics_args, 16, 4).decode_u32(0)
		_mutex.lock(); result["hashes"] = hashes; result["precision_guard"] = guard; _mutex.unlock())
	return result

func _release() -> void:
	_free_graphics_images()
	_free_graphics_pipelines()
	if _graphics_sampler.is_valid(): _rd.free_rid(_graphics_sampler)
	if _graphics_args.is_valid(): _rd.free_rid(_graphics_args); allocation_bytes -= 32
	_graphics_sampler = RID(); _graphics_args = RID()
	graphics_format_support = {}
	super._release()
