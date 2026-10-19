extends "res://lie_wall24_graphics_effect.gd"
## Two independently executable renderers, with one validated scene/control
## path and the same shared light transport. Reference resources are retained
## for A/B; their residency is reported separately from native resources.
const DirectRenderer = preload("res://lie_direct_renderer.gd")
var direct_backend: String = "surface"
var effective_direct_backend: String = "surface"
var direct_failure: String = ""
var direct_renderer: RefCounted
var _native_size: int = 0
var _native_lights: int = 0
var _native_borrowed: Array[RID] = []
var _direct_backend: String = "surface"
var _native_geometry := PackedByteArray()
var _native_transport_serial: int = -1
var _last_direct_event: Dictionary = {}
var native_stages = PassProfile.new()

func set_direct_backend(value: String) -> bool:
    if value not in ["reference","surface","regions","envelope"]: return false
    if value == direct_backend: return true
    direct_backend = value
    if gpu_ready: RenderingServer.call_on_render_thread(func():
        _direct_backend = value; _resident = PackedByteArray(); _geometry_resident = PackedByteArray(); _shade_dirty = true; _response_valid = false)
    return true

func _initialize() -> bool:
    _direct_backend = direct_backend
    return super._initialize()

func _ensure_native() -> bool:
    var borrowed: Array[RID] = [_images[9],_buffers[21],transport.output_rid,transport.material_codes_rid(),transport.surface_light_codes_rid(),transport.emission_descriptors_rid()]
    if direct_renderer != null and (_native_size != render_size or _native_lights != transport.desired_light_count or _native_borrowed != borrowed):
        direct_renderer.release(); direct_renderer = null
    if direct_renderer == null:
        if direct_failure != "" and _native_size == render_size and _native_lights == transport.desired_light_count: return false
        direct_renderer = DirectRenderer.new(); _native_size = render_size; _native_lights = transport.desired_light_count
        if not direct_renderer.initialize(_rd,catalog,render_size,transport,_images[9],_buffers[21]):
            direct_failure = direct_renderer.failure; direct_renderer.release(); direct_renderer = null; return false
        _native_borrowed = borrowed; direct_failure = ""
    return true

func prepare_stream_comparison() -> void:
    super.prepare_stream_comparison()
    if gpu_ready: RenderingServer.call_on_render_thread(func():
        if direct_renderer != null: direct_renderer.invalidate()
        _resident = PackedByteArray())

func force_geometry_rebuild() -> void:
    super.force_geometry_rebuild()
    if gpu_ready: RenderingServer.call_on_render_thread(func():
        if direct_renderer != null: direct_renderer.invalidate()
        _resident = PackedByteArray())

func _render_callback(type: int, data: RenderData) -> void:
    if not capture_loaded or (not gpu_ready and not _initialize()): return
    if _direct_backend == "reference":
        effective_direct_backend = "reference"; super._render_callback(type,data)
        if frame_count > 0:
            solve_profile.set_context(frame_count,{"event_kind":_profile_event_kind,"internal_size":render_size,"direct_backend":"reference","timing_scope":"whole_appearance"})
        return
    _mutex.lock(); var next: Dictionary = _pending.duplicate(); _mutex.unlock()
    if next.is_empty() or next["parameters"].decode_s32(88) != render_size: return
    _collect_profile()
    var params: PackedByteArray = next["parameters"]
    var signature: PackedByteArray = params.duplicate(); signature.append_array(next["instances"]); signature.append_array(next["jobs"])
    signature.append_array(PackedInt64Array([transport.frame_count]).to_byte_array())
    if signature == _resident: return
    if not _ensure_native():
        effective_direct_backend = "reference_fallback"; super._render_callback(type,data); return
    effective_direct_backend = _direct_backend
    var geometry: PackedByteArray = params.slice(0,96)
    _profile_event_kind = "geometry" if geometry != _native_geometry else "lighting"
    var serial: int = frame_count + 1
    _rd.buffer_update(_buffers[6],0,256,params)
    _rd.capture_timestamp(solve_profile.marker(-get_instance_id(),serial,"solve","begin"))
    _last_direct_event = direct_renderer.render(params,transport, bool(params.decode_float(144)>.5),material_response,false,_direct_backend,native_stages if _gpu_stage_timestamps else null,get_instance_id(),serial)
    if _gpu_stage_timestamps: _rd.capture_timestamp(native_stages.marker(get_instance_id(),serial,"output","begin"))
    var list: int = _rd.compute_list_begin()
    # Only the common output filter/tone mapper follows unified lighting.
    _rd.compute_list_bind_compute_pipeline(list,_kernels[7]["pipeline"])
    _rd.compute_list_bind_uniform_set(list,_kernel_sets[7],0)
    _rd.compute_list_set_push_constant(list,PackedInt32Array([7,2,0,0]).to_byte_array(),16)
    _rd.compute_list_dispatch(list,ceili(float(output_size*output_size)/64.),1,1)
    _rd.compute_list_end()
    if _gpu_stage_timestamps: _rd.capture_timestamp(native_stages.marker(get_instance_id(),serial,"output","end"))
    _rd.capture_timestamp(solve_profile.marker(-get_instance_id(),serial,"solve","end"))
    var context: Dictionary = {"event_kind":_profile_event_kind,"internal_size":render_size,"direct_backend":_direct_backend,"stage_timestamps":_gpu_stage_timestamps,"timing_scope":"whole_appearance","primary_build":_last_direct_event["primary_build"],"shadow_build":_last_direct_event["shadow_build"]}
    solve_profile.set_context(serial,context); native_stages.set_context(serial,context)
    _resident = signature; _native_geometry = geometry; sample_invocations = 0; instance_count = 97; frame_count += 1
    lighting_resolves += 1; output_resolves += 1
    if _last_direct_event["primary_build"]: geometry_rebuilds += 1

func _collect_profile() -> void:
    super._collect_profile()
    native_stages.collect(_rd,get_instance_id())

func cache_metrics() -> Dictionary:
    var result: Dictionary = super.cache_metrics()
    result["direct_surface"] = {"requested_backend":direct_backend,"effective_backend":effective_direct_backend,"failure":direct_failure,"source_bank_sha256":catalog.get("sha256",""),"atlas_resident":direct_renderer!=null,"additional_requested_bytes":direct_renderer.requested_bytes if direct_renderer!=null else 0,"primary_builds":direct_renderer.primary_builds if direct_renderer!=null else 0,"shadow_builds":direct_renderer.shadow_builds if direct_renderer!=null else 0,"shadow_light_builds":direct_renderer.shadow_light_builds if direct_renderer!=null else 0,"node_builds":direct_renderer.node_builds if direct_renderer!=null else 0,"shade_builds":direct_renderer.shade_builds if direct_renderer!=null else 0,"source_projection_dispatches":0,"source_shadow_queries":0,"native_shadow_size":512,"compiled_layers":4,"proxy_triangles":97*12,"scope":"experimental opaque compiled surface; native depth; four captured layers; shared full brick master replaces sparse instance selections; light-space cube maps replace short disk shadows; finite-resolution visibility differs; reference resources retained for A/B; no physical FPS claim"}
    if direct_renderer != null:
        var access: Dictionary = direct_renderer.access_proof
        result["direct_surface"]["access"] = access
        result["direct_surface"]["submitted_triangles"] = int(access["envelope_groups"][0]["triangles"])*96+int(access["envelope_groups"][1]["triangles"]) if effective_direct_backend=="envelope" else 1164
        result["direct_surface"]["fragment_depth_search"] = effective_direct_backend in ["surface","regions"]
    return result

func _capture() -> void:
    if effective_direct_backend not in ["surface","regions","envelope"] or direct_renderer == null: super._capture(); return
    _collect_profile()
    var native: Dictionary = direct_renderer.capture()
    var result: Dictionary = {"color":_rd.texture_get_data(output_rid,0).to_float32_array(),"depth":native["native_depth"].to_byte_array().to_int32_array(),"output_size":output_size,"internal_size":render_size,"asset_uploads":asset_uploads,"allocation_bytes":allocation_bytes+direct_renderer.requested_bytes,"frames":frame_count,"sample_invocations":0,"instances":97,"device":_rd.get_device_name(),"profile":_profiles.duplicate(),"library_bytes":_samples.size(),"cache":cache_metrics(),"whole_appearance":solve_profile.snapshot(),"native_surface":native,"recovered_pixels":0,"recovery_overflow":0}
    _mutex.lock(); _readback = result; _mutex.unlock()

func _release() -> void:
    if direct_renderer != null: direct_renderer.release(); direct_renderer = null
    super._release()
