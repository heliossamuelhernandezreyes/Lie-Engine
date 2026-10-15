extends "res://lie_wall15_active_effect.gd"
const QueryShader=preload("res://shaders/lie_wall16_query.glsl")
const QueryPlan=preload("res://lie_surface_query_plan.gd")
var surface_queries: bool=true
var occlusion_witnesses: bool=true
var _gpu_queries: bool=true
var _gpu_witnesses: bool=true
var surface_plan=QueryPlan.new()
var _query_control:=PackedByteArray()
var _bounds_dirty: bool=true
var bounds_builds: int=0
var selections: int=0
var query_supported: bool=true
var storage_buffer_limit: int=0
func shader_resource() -> RDShaderFile:
    if _rd!=null:
        storage_buffer_limit=_rd.limit_get(RenderingDevice.LIMIT_MAX_STORAGE_BUFFERS_PER_SHADER_STAGE)
        query_supported=storage_buffer_limit>=32
    return QueryShader if query_supported else super.shader_resource()
func _make_set() -> void:
    if not query_supported:super._make_set();return
    if not _buffers.has(36):
        var capacity: int=_schedule_bytes.size()/8
        var bounds_offset: int=ceili(float(4+capacity)/4.)*4
        var size: int=bounds_offset*4+(capacity+ceili(float(capacity)/16.))*64
        var rid: RID=_rd.storage_buffer_create(size,PackedByteArray(),RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
        _buffers[36]=rid;_lengths[36]=size;allocation_bytes+=size
        _buffer(39,256+_reference_count*32)
        _gpu_queries=surface_queries;_gpu_witnesses=occlusion_witnesses
    super._make_set()
func set_query_options(hierarchy: bool,witnesses: bool) -> void:
    if surface_queries==hierarchy and occlusion_witnesses==witnesses:return
    var changed: bool=surface_queries!=hierarchy
    surface_queries=hierarchy;occlusion_witnesses=witnesses
    if gpu_ready:RenderingServer.call_on_render_thread(func():
        _gpu_queries=hierarchy;_gpu_witnesses=witnesses
        if changed:_geometry_resident=PackedByteArray()
        _reset_coded_signature())
func _render_callback(type: int,data: RenderData) -> void:
    if not capture_loaded or (not gpu_ready and not _initialize()):return
    if not query_supported:super._render_callback(type,data);return
    _mutex.lock();var next: Dictionary=_pending.duplicate();_mutex.unlock()
    if next.is_empty():return
    var jobs: PackedByteArray=next["jobs"];var schedule: Dictionary=_schedules.get(jobs.decode_u32(4),{})
    if schedule.is_empty():return
    var groups: int=schedule["groups"];var pages: int=ceili(float(groups)/16.)
    var control: PackedByteArray=PackedInt32Array([int(_gpu_queries),int(_gpu_witnesses),int(_gpu_diagnostics),groups,pages,schedule["offset"],ceili(float(4+_schedule_bytes.size()/8)/4.)*4,0]).to_byte_array()
    if control!=_query_control:_rd.buffer_update(_buffers[39],0,32,control);_query_control=control
    if _gpu_queries and surface_plan.prepare(catalog["sha256"]+str(_gpu_continuity),next["instances"],next["parameters"].slice(208,256),jobs):_bounds_dirty=true
    super._render_callback(type,data)
func _stage(list: int,stage: int,count: int) -> void:
    _measured_options["surface_queries"]=_gpu_queries and query_supported;_measured_options["occlusion_witnesses"]=_gpu_witnesses and query_supported
    super._stage(list,stage,count)
func _timed_stage(list: int,stage: int,count: int,name: String) -> void:
    if not query_supported:super._timed_stage(list,stage,count,name);return
    if stage==10:
        _extra_stage(list,13,64,"visibility_keys");_extra_stage(list,12,_reference_count,"visibility_invalidate")
        _rd.capture_timestamp(pass_profile.marker(get_instance_id(),frame_count+1,"world_visibility","begin"))
        var flags: int=(1 if _gpu_active else 0)+(2 if _gpu_boxes else 0)
        _rd.compute_list_set_push_constant(list,PackedInt32Array([11,2,_coverage_mode,flags]).to_byte_array(),16)
        if _gpu_active:_rd.compute_list_dispatch_indirect(list,_buffers[35],0)
        else:_rd.compute_list_dispatch(list,ceili(float(_source_work)/64.),1,1)
        _rd.compute_list_add_barrier(list);_rd.capture_timestamp(pass_profile.marker(get_instance_id(),frame_count+1,"world_visibility","end"))
        _extra_stage(list,10,count,name);return
    if _gpu_queries and stage in [2,3]:
        if stage==2:
            var groups: int=_active_schedule["groups"];var pages: int=ceili(float(groups)/16.)
            if _bounds_dirty:
                _extra_stage(list,18,groups*64,"surface_bounds");_extra_stage(list,19,pages,"surface_parents")
                _bounds_dirty=false;bounds_builds+=1
            _extra_stage(list,17,pages,"surface_select");selections+=1
        _rd.capture_timestamp(pass_profile.marker(get_instance_id(),frame_count+1,name,"begin"))
        _rd.compute_list_set_push_constant(list,PackedInt32Array([stage,2,_coverage_mode,-1]).to_byte_array(),16)
        _rd.compute_list_dispatch_indirect(list,_buffers[36],0);_rd.compute_list_add_barrier(list)
        _rd.capture_timestamp(pass_profile.marker(get_instance_id(),frame_count+1,name,"end"));return
    super._timed_stage(list,stage,count,name)
func cache_metrics() -> Dictionary:
    var result: Dictionary=super.cache_metrics()
    result["surface_queries"]={"supported":query_supported,"storage_buffer_limit":storage_buffer_limit,"required_storage_buffers":32,"enabled":surface_queries and query_supported,"occlusion_witnesses":occlusion_witnesses and query_supported,"bounds_builds":bounds_builds,"selections":selections,"world_plan":surface_plan.metrics(),"witness_bytes":256+_reference_count*32 if query_supported else 0,"scope":"resident world centers/normal intervals; 16-block parents; exact captured-disk blocking witnesses; below 32 storage descriptors use the accepted 1.2 shader"}
    return result
func _capture() -> void:
    super._capture()
    if not gpu_ready:return
    if not query_supported:
        _mutex.lock();_readback["surface_queries"]={"supported":false,"selected_blocks":0,"total_blocks":0,"witness_hits":0};_mutex.unlock();return
    var work: PackedInt32Array=_rd.buffer_get_data(_buffers[36],0,16).to_int32_array()
    var stats: PackedInt32Array=_rd.buffer_get_data(_buffers[39],64,16).to_int32_array()
    _mutex.lock();_readback["surface_queries"]={"selected_blocks":work[0],"total_blocks":_active_schedule.get("groups",0),"bounds_builds":bounds_builds,"selections":selections,"witness_attempts":stats[0],"witness_hits":stats[1],"full_traversals":stats[2],"new_witnesses":stats[3],"instrumented":_gpu_diagnostics};_mutex.unlock()
