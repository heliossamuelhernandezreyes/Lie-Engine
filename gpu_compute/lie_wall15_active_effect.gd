extends "res://lie_wall13_area_effect.gd"
const ActiveShader=preload("res://shaders/lie_wall15_active.glsl")
var active_visibility: bool=true
var precomputed_ray_boxes: bool=true
var _gpu_active: bool=true
var _gpu_boxes: bool=true
var queue_builds: int=0
func shader_resource() -> RDShaderFile:return ActiveShader
func _make_set() -> void:
    if not _buffers.has(35):
        var bytes: int=16+MAX_WORK*4
        var rid: RID=_rd.storage_buffer_create(bytes,PackedByteArray(),RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
        if not rid.is_valid():failure="Active visibility queue allocation";return
        _buffers[35]=rid;_lengths[35]=bytes;allocation_bytes+=bytes
        _gpu_active=active_visibility;_gpu_boxes=precomputed_ray_boxes
    super._make_set()
func set_work_options(active: bool,boxes: bool) -> void:
    if active_visibility==active and precomputed_ray_boxes==boxes:return
    var rebuild: bool=active_visibility!=active
    active_visibility=active;precomputed_ray_boxes=boxes
    if gpu_ready:RenderingServer.call_on_render_thread(func():
        if not gpu_ready:return
        var invalidate: bool=_gpu_boxes!=boxes
        _gpu_active=active;_gpu_boxes=boxes
        if rebuild:_geometry_resident=PackedByteArray()
        if invalidate and not _shadow_lease.is_empty():_rd.buffer_update(_shadow_lease["rid"],4,4,PackedInt32Array([0]).to_byte_array())
        _reset_coded_signature())
func _stage(list: int,stage: int,count: int) -> void:
    _measured_options["active_visibility"]=_gpu_active;_measured_options["precomputed_ray_boxes"]=_gpu_boxes
    super._stage(list,stage,count)
    if stage==3 and _gpu_active:
        _extra_stage(list,16,render_size*render_size,"visibility_compact");queue_builds+=1
func _timed_stage(list: int,stage: int,count: int,name: String) -> void:
    if stage!=10:super._timed_stage(list,stage,count,name);return
    # Existing keys/invalidations remain per stable source and physical light.
    _extra_stage(list,13,64,"visibility_keys")
    _extra_stage(list,12,_reference_count,"visibility_invalidate")
    _rd.capture_timestamp(pass_profile.marker(get_instance_id(),frame_count+1,"world_visibility","begin"))
    var flags: int=(1 if _gpu_active else 0)+(2 if _gpu_boxes else 0)
    _rd.compute_list_set_push_constant(list,PackedInt32Array([11,2,_coverage_mode,flags]).to_byte_array(),16)
    if _gpu_active:_rd.compute_list_dispatch_indirect(list,_buffers[35],0)
    else:_rd.compute_list_dispatch(list,ceili(float(_source_work)/64.),1,1)
    _rd.compute_list_add_barrier(list)
    _rd.capture_timestamp(pass_profile.marker(get_instance_id(),frame_count+1,"world_visibility","end"))
    _extra_stage(list,10,count,name)
func cache_metrics() -> Dictionary:
    var result: Dictionary=super.cache_metrics()
    result["active_work"]={"enabled":active_visibility,"precomputed_ray_boxes":precomputed_ray_boxes,"queue_builds":queue_builds,"queue_capacity":MAX_WORK,"queue_requested_bytes":16+MAX_WORK*4,"gpu_indirect_dispatch":true,"scope":"unique final pixel winners; reused on light-only updates; unchanged captured primitive tests"}
    return result
func _capture() -> void:
    super._capture()
    if not gpu_ready:return
    var header: PackedInt32Array=_rd.buffer_get_data(_buffers[35],0,16).to_int32_array()
    _mutex.lock();_readback["active_work"]={"count":header[3],"groups":header[0],"enabled":_gpu_active,"precomputed_ray_boxes":_gpu_boxes,"source_work":sample_invocations};_mutex.unlock()
