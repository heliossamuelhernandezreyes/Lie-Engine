extends "res://lie_wall20_bounds_effect.gd"
const ShadowView=preload("res://lie_shared_shadow_view.gd")
const CompactKernels=preload("res://lie_shadow_view_kernels.gd")
var compact_shadows: bool=false
var _gpu_compact: bool=false
var _compact_document: Dictionary={}
var _compact_lease: Dictionary={}
var _compact_pipelines: Dictionary={}
var _compact_sets: Dictionary={}
func _init(size: int=720) -> void:
    super._init(size)
    if not capture_loaded:return
    _compact_document=ShadowView.load_document(capture_root(),catalog)
    if _compact_document.is_empty():failure="Compact shadow view identity contract";capture_loaded=false
func _initialize() -> bool:
    _gpu_compact=compact_shadows
    var ok: bool=super._initialize()
    if ok and query_supported and _compact_sets.size()!=6:failure="Compact shadow pipelines: "+failure;_release();return false
    return ok
func _free_compact_sets() -> void:
    for rid in _compact_sets.values():
        if rid.is_valid() and _rd.uniform_set_is_valid(rid):_rd.free_rid(rid)
    _compact_sets.clear()
func _make_set() -> void:
    _free_compact_sets();super._make_set()
    if not query_supported or not _kernels_ready or _tangent_lease.is_empty():return
    if _compact_lease.is_empty():
        _compact_lease=ShadowView.acquire(_rd,_compact_document)
        if _compact_lease.is_empty():failure="Compact shadow allocation";return
        allocation_bytes+=int(_compact_lease["bytes"])
    if _compact_pipelines.is_empty():
        for name in CompactKernels.SHADERS:
            var spirv: RDShaderSPIRV=CompactKernels.SHADERS[name].get_spirv();var error: String=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
            if error!="":failure=name+": "+error;return
            var shader: RID=_rd.shader_create_from_spirv(spirv);var pipeline: RID=_rd.compute_pipeline_create(shader)
            _compact_pipelines[name]={"shader":shader,"pipeline":pipeline}
            if not pipeline.is_valid():failure=name+" compact pipeline";return
            if name in ["prepare","trace"]:
                var option:=RDPipelineSpecializationConstant.new();option.constant_id=0;option.value=true
                var options: Array[RDPipelineSpecializationConstant]=[option]
                var instrumented: RID=_rd.compute_pipeline_create(shader,options)
                _compact_pipelines[name]["instrumented"]=instrumented
                if not instrumented.is_valid():failure=name+" compact instrumented pipeline";return
    var handles: Dictionary=_buffers.duplicate();handles[0]=_compact_lease["rid"];handles[23]=transport.surface_light_codes_rid();handles[26]=_visibility_lease["leaves"];handles[30]=_shadow_lease["rid"];handles[38]=_trace_queue
    for tight in [false,true]:
        handles[25]=_tangent_lease["rid"] if tight else _visibility_lease["nodes"]
        for name in CompactKernels.SHADERS:
            var uniforms: Array[RDUniform]=[]
            for binding in CompactKernels.BINDINGS[name]:uniforms.append(_uniform(binding,handles[binding]))
            var rid: RID=_rd.uniform_set_create(uniforms,_compact_pipelines[name]["shader"],0)
            if not rid.is_valid():failure=name+" compact descriptors";return
            _compact_sets[name+str(tight)]=rid
func set_compact_shadows(enabled: bool) -> void:
    if compact_shadows==enabled:return
    compact_shadows=enabled
    if gpu_ready:RenderingServer.call_on_render_thread(func():
        if not gpu_ready:return
        _gpu_compact=enabled;_geometry_resident=PackedByteArray();_resident=PackedByteArray();_shade_dirty=true
        if query_supported:_rd.buffer_clear(_buffers[39],256,_reference_count*32)
        _rd.buffer_update(_shadow_lease["rid"],4,4,PackedInt32Array([0]).to_byte_array()))
func _effective_compact() -> bool:return _gpu_compact and query_supported and _gpu_kernel_mode=="split"
func _dispatch_kernel(list: int,stage: int,count: int,name: String,flags: int=0,indirect: int=-1) -> void:
    if stage!=11 or not _effective_compact():super._dispatch_kernel(list,stage,count,name,flags,indirect);return
    _pass_timestamp(name,"begin")
    _rd.compute_list_bind_compute_pipeline(list,_compact_pipelines["visibility"]["pipeline"])
    _rd.compute_list_bind_uniform_set(list,_compact_sets["visibility"+str(_gpu_tight_bounds)],0)
    _rd.compute_list_set_push_constant(list,PackedInt32Array([stage,2,_coverage_mode,flags]).to_byte_array(),16)
    if indirect>=0:_rd.compute_list_dispatch_indirect(list,_buffers[indirect],0)
    else:
        var groups: int=ceili(float(count)/64.);var gx: int=mini(groups,65535)
        _rd.compute_list_dispatch(list,gx,ceili(float(groups)/float(gx)),1)
    _pass_barrier(list);_pass_timestamp(name,"end")
func _stream_dispatch(list: int,key: String,count: int,label: String,light: int=0,flags: int=0,indirect: RID=RID()) -> void:
    if key not in ["prepare","trace"] or not _effective_compact():super._stream_dispatch(list,key,count,label,light,flags,indirect);return
    _pass_timestamp(label,"begin")
    var entry: Dictionary=_compact_pipelines[key];var pipeline: RID=entry["instrumented"] if _gpu_diagnostics else entry["pipeline"]
    _rd.compute_list_bind_compute_pipeline(list,pipeline);_rd.compute_list_bind_uniform_set(list,_compact_sets[key+str(_gpu_tight_bounds)],0)
    _rd.compute_list_set_push_constant(list,PackedInt32Array([0,2,light,flags]).to_byte_array(),16)
    if indirect.is_valid():_rd.compute_list_dispatch_indirect(list,indirect,0)
    else:_rd.compute_list_dispatch(list,maxi(1,ceili(float(count)/64.)),1,1)
    _pass_barrier(list);_pass_timestamp(label,"end")
func _stage(list: int,stage: int,count: int) -> void:
    _measured_options["compact_shadows"]=_effective_compact();super._stage(list,stage,count)
func cache_metrics() -> Dictionary:
    var result: Dictionary=super.cache_metrics()
    result["compact_shadows"]={"requested":compact_shadows,"effective":compact_shadows and query_supported and kernel_mode=="split","ready":_compact_sets.size()==6,"additional_resident_bytes":int(_compact_document.get("proof",{}).get("bytes",0)),"sha256":_compact_document.get("proof",{}).get("sha256",""),"source_stride_bytes":80,"shadow_stride_bytes":32,"scope":"extra shared immutable view; exact original position/radius/normal bits and IDs; original bank retained; actual bandwidth gain must be measured"};return result
func _release() -> void:
    _free_compact_sets()
    for item in _compact_pipelines.values():
        for rid in [item["pipeline"],item.get("instrumented",RID()),item["shader"]]:
            if rid.is_valid():_rd.free_rid(rid)
    _compact_pipelines.clear();super._release()
    if not _compact_lease.is_empty():ShadowView.release(_rd,_compact_lease["key"]);_compact_lease={}
