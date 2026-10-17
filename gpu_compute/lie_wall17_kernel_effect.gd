extends "res://lie_wall16_query_effect.gd"
const Kernels=preload("res://lie_stage_kernels.gd")
var kernel_mode: String="split"
var _gpu_kernel_mode: String="split"
var _kernels: Dictionary={}
var _kernel_sets: Dictionary={}
var _kernels_ready: bool=false
var kernel_set_builds: int=0
func _initialize() -> bool:
    _gpu_kernel_mode=kernel_mode
    var ok: bool=super._initialize()
    if ok and query_supported and not _kernels_ready:
        failure="Dedicated kernel initialization: "+failure;_release();return false
    return ok
func _make_set() -> void:
    super._make_set()
    if not query_supported or not _set.is_valid():return
    for rid in _kernel_sets.values():
        if _rd.uniform_set_is_valid(rid):_rd.free_rid(rid)
    _kernel_sets.clear();_kernels_ready=false
    if _kernels.is_empty():
        var resources: Dictionary=Kernels.SHADERS.duplicate();resources[0]=Kernels.LEGACY
        for stage in resources:
            var spirv: RDShaderSPIRV=resources[stage].get_spirv()
            var error: String=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
            if error!="":failure="Stage %d: %s" % [stage,error];return
            var shader: RID=_rd.shader_create_from_spirv(spirv)
            if not shader.is_valid():failure="Stage shader "+str(stage);return
            var pipeline: RID=_rd.compute_pipeline_create(shader)
            _kernels[stage]={"shader":shader,"pipeline":pipeline}
            if not pipeline.is_valid():failure="Stage pipeline "+str(stage);return
    var handles: Dictionary=_buffers.duplicate();handles.merge(_images)
    handles[14]=transport.output_rid;handles[15]=transport.material_codes_rid()
    handles[23]=transport.surface_light_codes_rid();handles[25]=_visibility_lease["nodes"];handles[26]=_visibility_lease["leaves"]
    handles[30]=_shadow_lease["rid"];handles[34]=transport.emission_descriptors_rid()
    for stage in _kernels:
        var uniforms: Array[RDUniform]=[]
        var bindings: Array=Kernels.LEGACY_BINDINGS if stage==0 else Kernels.BINDINGS[stage]
        for binding in bindings:uniforms.append(_uniform(binding,handles[binding],binding in [8,9,11,12,14]))
        var rid: RID=_rd.uniform_set_create(uniforms,_kernels[stage]["shader"],0)
        _kernel_sets[stage]=rid
        if not rid.is_valid():failure="Stage uniform set "+str(stage);return
    kernel_set_builds+=1;_kernels_ready=true
func set_kernel_mode(mode: String) -> bool:
    if mode not in ["legacy","monolithic","split"]:return false
    if mode==kernel_mode:return true
    kernel_mode=mode
    if gpu_ready:RenderingServer.call_on_render_thread(func():
        if not gpu_ready:return
        _gpu_kernel_mode=mode;_geometry_resident=PackedByteArray();_resident=PackedByteArray();_shade_dirty=true
        # Every mode starts from the same fully invalidated source cache.
        _rd.buffer_update(_shadow_lease["rid"],4,4,PackedInt32Array([0]).to_byte_array()))
    return true
func _stage(list: int,stage: int,count: int) -> void:
    _measured_options["kernel_mode"]=_gpu_kernel_mode if query_supported else "legacy_fallback"
    super._stage(list,stage,count)
    _measured_options["surface_queries"]=_gpu_queries and query_supported and _gpu_kernel_mode!="legacy"
    _measured_options["occlusion_witnesses"]=_gpu_witnesses and query_supported and _gpu_kernel_mode!="legacy"
    var context: Dictionary=_measured_options.duplicate();context["internal_size"]=render_size;context["event_kind"]=_profile_event_kind
    pass_profile.set_context(frame_count+1,context)
func _pass_timestamp(name: String,edge: String) -> void:
    _rd.capture_timestamp(pass_profile.marker(get_instance_id(),frame_count+1,name,edge))
func _pass_barrier(list: int) -> void:
    _rd.compute_list_add_barrier(list)
func _dispatch_kernel(list: int,stage: int,count: int,name: String,flags: int=0,indirect: int=-1) -> void:
    _pass_timestamp(name,"begin")
    if query_supported and _kernels_ready and _gpu_kernel_mode!="monolithic":
        var key: int=0 if _gpu_kernel_mode=="legacy" else stage
        _rd.compute_list_bind_compute_pipeline(list,_kernels[key]["pipeline"])
        _rd.compute_list_bind_uniform_set(list,_kernel_sets[key],0)
    else:
        _rd.compute_list_bind_compute_pipeline(list,_pipeline);_rd.compute_list_bind_uniform_set(list,_set,0)
    _rd.compute_list_set_push_constant(list,PackedInt32Array([stage,2,_coverage_mode,flags]).to_byte_array(),16)
    if indirect>=0:_rd.compute_list_dispatch_indirect(list,_buffers[indirect],0)
    else:
        var groups: int=ceili(float(count)/64.);var gx: int=mini(groups,65535)
        _rd.compute_list_dispatch(list,gx,ceili(float(groups)/float(gx)),1)
    _pass_barrier(list)
    _pass_timestamp(name,"end")
func _extra_stage(list: int,stage: int,count: int,name: String) -> void:
    _dispatch_kernel(list,stage,count,name)
func _timed_stage(list: int,stage: int,count: int,name: String) -> void:
    if stage==10:
        _extra_stage(list,13,64,"visibility_keys");_extra_stage(list,12,_reference_count,"visibility_invalidate")
        var flags: int=(1 if _gpu_active else 0)+(2 if _gpu_boxes else 0)
        _dispatch_kernel(list,11,_source_work,"world_visibility",flags,35 if _gpu_active else -1)
    if stage in [2,3]:
        if _gpu_kernel_mode!="legacy" and _gpu_queries and query_supported:
            if stage==2:
                var groups: int=_active_schedule["groups"];var pages: int=ceili(float(groups)/16.)
                if _bounds_dirty:
                    _extra_stage(list,18,groups*64,"surface_bounds");_extra_stage(list,19,pages,"surface_parents")
                    _bounds_dirty=false;bounds_builds+=1
                _extra_stage(list,17,pages,"surface_select");selections+=1
            _dispatch_kernel(list,stage,count,name,-1,36);return
        if _gpu_blocks:
            _dispatch_kernel(list,stage,int(_active_schedule["groups"])*64,name,int(_active_schedule["offset"])+1);return
    _dispatch_kernel(list,stage,count,"fused_base" if stage==4 and _gpu_fused else name)
func cache_metrics() -> Dictionary:
    var result: Dictionary=super.cache_metrics()
    result["kernels"]={"requested_mode":kernel_mode,"effective_mode":_gpu_kernel_mode if query_supported else "legacy_fallback","dedicated_count":Kernels.SHADERS.size(),"ready":_kernels_ready,"set_builds":kernel_set_builds,"extra_surface_buffer_bytes":0,"scope":"independent stage entry points and reachable helpers; exact original equations; real 1.2 and 1.3 comparison binaries"}
    return result
func _release() -> void:
    for rid in _kernel_sets.values():
        if _rd.uniform_set_is_valid(rid):_rd.free_rid(rid)
    _kernel_sets.clear()
    for entry in _kernels.values():
        for rid in [entry["pipeline"],entry["shader"]]:
            if rid.is_valid():_rd.free_rid(rid)
    _kernels.clear();_kernels_ready=false
    super._release()
