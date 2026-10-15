extends "res://lie_wall12_material_effect.gd"
const AreaShader=preload("res://shaders/lie_wall13_area.glsl")
var fused_shading: bool=true
var surface_filter: bool=true
var _gpu_fused: bool=true
var _gpu_filter: bool=true
var _material_dirty: bool=true
var _filter_recovery_dirty: bool=false
var material_builds: int=0
var material_reuses: int=0
func shader_resource() -> RDShaderFile:return AreaShader
func _pipeline_bytes() -> PackedByteArray:return PackedInt32Array([1 if fused_shading else 0,1 if surface_filter else 0,0,0]).to_byte_array()
func _make_set() -> void:
    var format: RDTextureFormat=_rd.texture_get_format(_images[8])
    if format.format!=RenderingDevice.DATA_FORMAT_R32G32B32A32_UINT:
        if _set.is_valid():_rd.free_rid(_set);_set=RID()
        _rd.free_rid(_images[8]);format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_UINT
        _images[8]=_rd.texture_create(format,RDTextureView.new(),[])
        _material_dirty=true
    if not _buffers.has(33):
        _buffer(33,16,_pipeline_bytes());_gpu_fused=fused_shading;_gpu_filter=surface_filter
    _buffers[34]=transport.emission_descriptors_rid()
    super._make_set();_buffers.erase(34)
func set_pipeline_options(fused: bool,filtered: bool) -> void:
    if fused_shading==fused and surface_filter==filtered:return
    var changed: bool=surface_filter!=filtered;fused_shading=fused;surface_filter=filtered
    var bytes: PackedByteArray=_pipeline_bytes()
    if gpu_ready:RenderingServer.call_on_render_thread(func():
        if not gpu_ready:return
        _rd.buffer_update(_buffers[33],0,16,bytes);_gpu_fused=fused;_gpu_filter=filtered
        if changed:_material_dirty=true;_filter_recovery_dirty=true
        _reset_coded_signature())
func _stage(list: int,stage: int,count: int) -> void:
    _measured_options["fused_shading"]=_gpu_fused;_measured_options["surface_filter"]=_gpu_filter
    if stage==1:_material_dirty=true;_filter_recovery_dirty=false
    if stage==6 and _gpu_fused:return
    if stage==4 and _filter_recovery_dirty:_extra_stage(list,15,count,"filter_recovery_clear")
    if stage==4:
        if _gpu_filter:
            if _material_dirty:_extra_stage(list,14,count,"material_filter");material_builds+=1
            else:material_reuses+=1
        _material_dirty=false
    if stage==9 and _filter_recovery_dirty:
        stage=8;_filter_recovery_dirty=false;recovery_reuses-=1;recovery_builds+=1
    super._stage(list,stage,count)
func _timed_stage(list: int,stage: int,count: int,name: String) -> void:
    if stage!=4:super._timed_stage(list,stage,count,name);return
    var label: String="fused_base" if _gpu_fused else name
    _rd.capture_timestamp(pass_profile.marker(get_instance_id(),frame_count+1,label,"begin"))
    _rd.compute_list_set_push_constant(list,PackedInt32Array([4,2,_coverage_mode,1 if _material_dirty else 0]).to_byte_array(),16)
    _rd.compute_list_dispatch(list,ceili(float(count)/64.),1,1);_rd.compute_list_add_barrier(list)
    _rd.capture_timestamp(pass_profile.marker(get_instance_id(),frame_count+1,label,"end"))
func cache_metrics() -> Dictionary:
    var result: Dictionary=super.cache_metrics()
    result["surface_pipeline"]={"fused":fused_shading,"filtered":surface_filter,"material_builds":material_builds,"material_reuses":material_reuses,"additional_full_frame_bytes":0,"material_packet_bytes_per_pixel":16}
    return result
func _release() -> void:
    super._release();_material_dirty=true;_filter_recovery_dirty=false
