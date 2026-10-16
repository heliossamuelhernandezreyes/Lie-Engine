extends "res://lie_wall17_kernel_effect.gd"
const PageShader=preload("res://shaders/lie_wall18_pages_11.glsl")
const SharedPages=preload("res://lie_shared_spatial_pages.gd")
var spatial_pages: bool=true
var _gpu_pages: bool=true
var _page_document: Dictionary={}
var _page_lease: Dictionary={}
var _page_shader:=RID()
var _page_pipeline:=RID()
var _page_set:=RID()
var page_set_builds: int=0
func _init(size: int=720) -> void:
    super._init(size)
    if not capture_loaded:return
    _page_document=SharedPages.load_document(capture_root(),catalog,_source_packets["proof"])
    if _page_document.is_empty():failure="Source-coordinate page contract";capture_loaded=false
func _initialize() -> bool:
    _gpu_pages=spatial_pages
    var ok: bool=super._initialize()
    if ok and query_supported and not _page_set.is_valid():failure="Spatial page pipeline: "+failure;_release();return false
    return ok
func _make_set() -> void:
    if _rd!=null and _page_set.is_valid() and _rd.uniform_set_is_valid(_page_set):_rd.free_rid(_page_set)
    _page_set=RID();super._make_set()
    if not query_supported or not _kernels_ready:return
    if _page_lease.is_empty():
        _page_lease=SharedPages.acquire(_rd,_page_document)
        if not _page_lease.get("ok",false):failure="Spatial page residency";return
        allocation_bytes+=int(_page_lease["bytes"])
    if not _page_shader.is_valid():
        var spirv: RDShaderSPIRV=PageShader.get_spirv()
        var error: String=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
        if error!="":failure=error;return
        _page_shader=_rd.shader_create_from_spirv(spirv);_page_pipeline=_rd.compute_pipeline_create(_page_shader)
        if not _page_pipeline.is_valid():failure="Spatial page compute pipeline";return
    var handles: Dictionary=_buffers.duplicate()
    handles[23]=transport.surface_light_codes_rid();handles[25]=_visibility_lease["nodes"];handles[26]=_visibility_lease["leaves"];handles[30]=_shadow_lease["rid"];handles[37]=_page_lease["rid"]
    var uniforms: Array[RDUniform]=[]
    for binding in Kernels.BINDINGS[11]+[37]:uniforms.append(_uniform(binding,handles[binding]))
    _page_set=_rd.uniform_set_create(uniforms,_page_shader,0);page_set_builds+=1
func set_spatial_pages(enabled: bool) -> void:
    if enabled==spatial_pages:return
    spatial_pages=enabled
    if gpu_ready:RenderingServer.call_on_render_thread(func():
        if not gpu_ready:return
        _gpu_pages=enabled;_reset_coded_signature()
        _rd.buffer_update(_shadow_lease["rid"],4,4,PackedInt32Array([0]).to_byte_array()))
func prepare_page_comparison() -> void:
    # Private witness hints start identically for both variants. The immutable
    # page index is retained; all reset work precedes the warm-up sequence.
    if gpu_ready:RenderingServer.call_on_render_thread(func():
        if not gpu_ready:return
        if query_supported:_rd.buffer_clear(_buffers[39],256,_reference_count*32)
        _rd.buffer_update(_shadow_lease["rid"],4,4,PackedInt32Array([0]).to_byte_array())
        _geometry_resident=PackedByteArray();_resident=PackedByteArray();_shade_dirty=true)
func _stage(list: int,stage: int,count: int) -> void:
    super._stage(list,stage,count)
    _measured_options["spatial_pages"]=_gpu_pages and query_supported and _gpu_kernel_mode=="split"
    var context: Dictionary=_measured_options.duplicate();context["internal_size"]=render_size;context["event_kind"]=_profile_event_kind
    pass_profile.set_context(frame_count+1,context)
func _dispatch_kernel(list: int,stage: int,count: int,name: String,flags: int=0,indirect: int=-1) -> void:
    if stage!=11 or not _gpu_pages or not query_supported or _gpu_kernel_mode!="split":super._dispatch_kernel(list,stage,count,name,flags,indirect);return
    _rd.capture_timestamp(pass_profile.marker(get_instance_id(),frame_count+1,name,"begin"))
    _rd.compute_list_bind_compute_pipeline(list,_page_pipeline);_rd.compute_list_bind_uniform_set(list,_page_set,0)
    _rd.compute_list_set_push_constant(list,PackedInt32Array([stage,2,_coverage_mode,flags|4]).to_byte_array(),16)
    if indirect>=0:_rd.compute_list_dispatch_indirect(list,_buffers[indirect],0)
    else:_rd.compute_list_dispatch(list,ceili(float(count)/64.),1,1)
    _rd.compute_list_add_barrier(list)
    _rd.capture_timestamp(pass_profile.marker(get_instance_id(),frame_count+1,name,"end"))
func cache_metrics() -> Dictionary:
    var result: Dictionary=super.cache_metrics()
    result["spatial_pages"]={"requested":spatial_pages,"effective":spatial_pages and query_supported and kernel_mode=="split","packet_bytes":int(_page_document.get("proof",{}).get("bytes",0)),"roots":_page_document.get("proof",{}).get("roots",[]),"shared":SharedPages.metrics(_rd),"set_builds":page_set_builds,"scope":"direct local cell -> original source IDs; immutable across camera/light/power changes; shared across instances; exact disk tests and original BLAS fallback"}
    return result
func _capture() -> void:
    super._capture()
    if not gpu_ready or not query_supported:return
    var stats: PackedInt32Array=_rd.buffer_get_data(_buffers[39],80,16).to_int32_array()
    _mutex.lock();_readback["page_work"]={"instrumented":_gpu_diagnostics,"cumulative_rays":stats[0],"cumulative_cells":stats[1],"cumulative_disk_tests":stats[2],"cumulative_fallbacks":stats[3]};_mutex.unlock()
func _release() -> void:
    if _page_set.is_valid() and _rd.uniform_set_is_valid(_page_set):_rd.free_rid(_page_set)
    _page_set=RID()
    for rid in [_page_pipeline,_page_shader]:
        if rid.is_valid():_rd.free_rid(rid)
    _page_pipeline=RID();_page_shader=RID()
    if not _page_lease.is_empty():SharedPages.release(_rd,_page_lease["key"]);_page_lease={}
    super._release()
