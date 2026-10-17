extends "res://lie_wall17_kernel_effect.gd"
const Stream=preload("res://lie_visibility_stream_kernels.gd")
const Order=preload("res://lie_shared_visibility_order.gd")
var visibility_stream: bool=false
var _gpu_stream: bool=false
var _stream_document: Dictionary={}
var _order_lease: Dictionary={}
var _trace_queue:=RID()
var _stream_pipelines: Dictionary={}
var _stream_sets: Dictionary={}
var _order_offset: int=0
var _work_readback: Dictionary={}
var stream_set_builds: int=0
func _init(size: int=720) -> void:
    super._init(size)
    if not capture_loaded:return
    _stream_document=Order.load_document(capture_root(),catalog,_source_packets["proof"])
    if _stream_document.is_empty():failure="Visibility order contract";capture_loaded=false
func _initialize() -> bool:
    _gpu_stream=visibility_stream
    var ok: bool=super._initialize()
    if ok and query_supported and _stream_sets.size()!=Stream.SHADERS.size():failure="Stream pipeline: "+failure;_release();return false
    return ok
func _make_set() -> void:
    for rid in _stream_sets.values():
        if _rd.uniform_set_is_valid(rid):_rd.free_rid(rid)
    _stream_sets.clear();super._make_set()
    if not query_supported or not _kernels_ready:return
    if _order_lease.is_empty():
        _order_lease=Order.acquire(_rd,_stream_document)
        if _order_lease.is_empty():failure="Visibility order allocation";return
        allocation_bytes+=int(_order_lease["bytes"])
    if not _trace_queue.is_valid():
        _trace_queue=_rd.storage_buffer_create(16+MAX_WORK*4,PackedByteArray(),RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
        if not _trace_queue.is_valid():failure="Visibility trace queue";return
        allocation_bytes+=16+MAX_WORK*4
    if _stream_pipelines.is_empty():
        for name in Stream.SHADERS:
            var spirv: RDShaderSPIRV=Stream.SHADERS[name].get_spirv();var error: String=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
            if error!="":failure=name+": "+error;return
            var shader: RID=_rd.shader_create_from_spirv(spirv);var pipeline: RID=_rd.compute_pipeline_create(shader)
            _stream_pipelines[name]={"shader":shader,"pipeline":pipeline}
            if not pipeline.is_valid():failure=name+" pipeline";return
            if name in ["prepare","trace"]:
                var option:=RDPipelineSpecializationConstant.new();option.constant_id=0;option.value=true
                var options: Array[RDPipelineSpecializationConstant]=[option]
                var instrumented: RID=_rd.compute_pipeline_create(shader,options)
                _stream_pipelines[name]["instrumented"]=instrumented
                if not instrumented.is_valid():failure=name+" instrumented pipeline";return
    var handles: Dictionary=_buffers.duplicate();handles[23]=transport.surface_light_codes_rid();handles[25]=_visibility_lease["nodes"];handles[26]=_visibility_lease["leaves"];handles[30]=_shadow_lease["rid"];handles[37]=_order_lease["rid"];handles[38]=_trace_queue
    for name in Stream.SHADERS:
        var uniforms: Array[RDUniform]=[]
        for binding in Stream.BINDINGS[name]:uniforms.append(_uniform(binding,handles[binding]))
        var rid: RID=_rd.uniform_set_create(uniforms,_stream_pipelines[name]["shader"],0)
        if not rid.is_valid():failure=name+" descriptors";return
        _stream_sets[name]=rid
    stream_set_builds+=1
func _effective_stream() -> bool:return _gpu_stream and query_supported and _gpu_active and _gpu_kernel_mode=="split"
func set_visibility_stream(enabled: bool) -> void:
    if enabled==visibility_stream:return
    visibility_stream=enabled
    if gpu_ready:RenderingServer.call_on_render_thread(func():
        if not gpu_ready:return
        _gpu_stream=enabled;_geometry_resident=PackedByteArray();_resident=PackedByteArray();_shade_dirty=true
        _rd.buffer_update(_shadow_lease["rid"],4,4,PackedInt32Array([0]).to_byte_array()))
func prepare_stream_comparison() -> void:
    if gpu_ready:RenderingServer.call_on_render_thread(func():
        if not gpu_ready:return
        if query_supported:_rd.buffer_clear(_buffers[39],256,_reference_count*32)
        _rd.buffer_update(_shadow_lease["rid"],4,4,PackedInt32Array([0]).to_byte_array())
        _geometry_resident=PackedByteArray();_resident=PackedByteArray();_shade_dirty=true)
func _render_callback(type: int,data: RenderData) -> void:
    if not capture_loaded:return
    _mutex.lock();var next: Dictionary=_pending.duplicate();_mutex.unlock()
    if not next.is_empty():_order_offset=_stream_document["levels"][next["jobs"].decode_u32(4)]["offset"]
    super._render_callback(type,data)
func _stream_dispatch(list: int,key: String,count: int,label: String,light: int=0,flags: int=0,indirect: RID=RID()) -> void:
    _pass_timestamp(label,"begin")
    var entry: Dictionary=_stream_pipelines[key]
    var pipeline: RID=entry.get("instrumented",entry["pipeline"]) if _gpu_diagnostics else entry["pipeline"]
    _rd.compute_list_bind_compute_pipeline(list,pipeline);_rd.compute_list_bind_uniform_set(list,_stream_sets[key],0)
    _rd.compute_list_set_push_constant(list,PackedInt32Array([0,2,light,flags]).to_byte_array(),16)
    if indirect.is_valid():_rd.compute_list_dispatch_indirect(list,indirect,0)
    else:_rd.compute_list_dispatch(list,maxi(1,ceili(float(count)/64.)),1,1)
    _pass_barrier(list);_pass_timestamp(label,"end")
func _dispatch_kernel(list: int,stage: int,count: int,name: String,flags: int=0,indirect: int=-1) -> void:
    if stage==16 and _effective_stream():_stream_dispatch(list,"mark",count,name);return
    super._dispatch_kernel(list,stage,count,name,flags,indirect)
func _stage(list: int,stage: int,count: int) -> void:
    super._stage(list,stage,count)
    if stage==3 and _effective_stream():_stream_dispatch(list,"compact",count,"visibility_order",0,_order_offset)
    _measured_options["visibility_stream"]=_effective_stream()
    var context: Dictionary=_measured_options.duplicate();context["internal_size"]=render_size;context["event_kind"]=_profile_event_kind;pass_profile.set_context(frame_count+1,context)
func _timed_stage(list: int,stage: int,count: int,name: String) -> void:
    if stage!=10 or not _effective_stream():super._timed_stage(list,stage,count,name);return
    _extra_stage(list,13,64,"visibility_keys");_extra_stage(list,12,_reference_count,"visibility_invalidate")
    for light in range(transport.desired_light_count):
        _stream_dispatch(list,"reset",64,"visibility_reset_"+str(light),light)
        _stream_dispatch(list,"prepare",0,"visibility_prepare_"+str(light),light,0,_buffers[35])
        _stream_dispatch(list,"trace",0,"world_visibility_"+str(light),light,2 if _gpu_boxes else 0,_trace_queue)
    _dispatch_kernel(list,10,count,name)
func request_work_counters() -> void:
    _mutex.lock();_work_readback={};_mutex.unlock()
    if not gpu_ready:return
    RenderingServer.call_on_render_thread(func():
        if not gpu_ready:return
        var data: Dictionary={"available":_effective_stream(),"instrumented":_gpu_diagnostics,"scope":"last stream solve; explicit 32-byte GPU counter read outside timed events"}
        if _effective_stream():
            var stats: PackedInt32Array=_rd.buffer_get_data(_buffers[39],96,32).to_int32_array();var names: Array=["eligible","cache_hits","backface_or_disabled","witness_hits","unresolved_queries","blas_nodes","disk_tests","scene_nodes"]
            for index in range(8):data[names[index]]=stats[index]
        _mutex.lock();_work_readback=data;_mutex.unlock())
func work_counters() -> Dictionary:
    _mutex.lock();var result: Dictionary=_work_readback.duplicate(true);_mutex.unlock();return result
func cache_metrics() -> Dictionary:
    var result: Dictionary=super.cache_metrics()
    result["visibility_stream"]={"requested":visibility_stream,"effective":visibility_stream and query_supported and active_visibility and kernel_mode=="split","ready":_stream_sets.size()==5,"set_builds":stream_set_builds,"order_bytes":int(_stream_document.get("proof",{}).get("bytes",0)),"trace_queue_bytes":16+MAX_WORK*4,"scope":"spatially ordered final winners; separate per-light cache/witness and exact BLAS kernels; 1.5 page traversal absent; original disks and shadow equations"};return result
func _release() -> void:
    for rid in _stream_sets.values():
        if _rd.uniform_set_is_valid(rid):_rd.free_rid(rid)
    _stream_sets.clear()
    for item in _stream_pipelines.values():
        for rid in [item["pipeline"],item.get("instrumented",RID()),item["shader"]]:
            if rid.is_valid():_rd.free_rid(rid)
    _stream_pipelines.clear()
    if _trace_queue.is_valid():_rd.free_rid(_trace_queue)
    _trace_queue=RID()
    if not _order_lease.is_empty():Order.release(_rd,_order_lease["key"]);_order_lease={}
    super._release()
