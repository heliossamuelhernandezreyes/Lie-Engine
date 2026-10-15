extends "res://lie_wall07_shared_effect.gd"
const SurfaceShader=preload("res://shaders/lie_wall09_surface.glsl")
const PassProfile=preload("res://lie_gpu_pass_profile.gd")
var contact_shadows: bool=true
var surface_detail: bool=true
var contact_steps: int=12
var pass_profile=PassProfile.new()
func shader_resource() -> RDShaderFile:return SurfaceShader
func _options() -> PackedByteArray:
    var bytes: PackedByteArray=PackedInt32Array([1 if contact_shadows else 0,1 if surface_detail else 0,contact_steps,0]).to_byte_array()
    bytes.append_array(PackedFloat32Array([.025,.0003,0.,0.]).to_byte_array());return bytes
func _make_set() -> void:
    if not _buffers.has(22):_buffer(22,32,_options())
    if not _buffers.has(24):_buffer(24,RECOVERY_CAPACITY*32)
    # Borrow transport's stable packet. It is never freed by this consumer.
    _buffers[23]=transport.surface_light_codes_rid()
    super._make_set();_buffers.erase(23)
func set_surface_options(contacts: bool,detail: bool,steps: int=12) -> void:
    steps=clampi(steps,4,32)
    if contact_shadows==contacts and surface_detail==detail and contact_steps==steps:return
    contact_shadows=contacts;surface_detail=detail;contact_steps=steps
    var bytes: PackedByteArray=_options()
    if gpu_ready:RenderingServer.call_on_render_thread(func():
        if not gpu_ready:return
        _rd.buffer_update(_buffers[22],0,32,bytes);_reset_coded_signature())
func _timed_stage(list: int,stage: int,count: int,name: String) -> void:
    _rd.capture_timestamp(pass_profile.marker(get_instance_id(),frame_count+1,name,"begin"))
    super._stage(list,stage,count)
    _rd.capture_timestamp(pass_profile.marker(get_instance_id(),frame_count+1,name,"end"))
func _stage(list: int,stage: int,count: int) -> void:
    var names: Dictionary={1:"clear",2:"project",3:"raster",4:"coarse_light",6:"compose",7:"output",8:"recovery_build",9:"recovery_reuse"}
    _timed_stage(list,stage,count,names.get(stage,str(stage)))
    if stage==8 or stage==9:_timed_stage(list,10,count,"surface_light")
func _collect_profile() -> void:
    super._collect_profile();pass_profile.collect(_rd,get_instance_id())
func cache_metrics() -> Dictionary:
    var result: Dictionary=super.cache_metrics()
    result["surface_light"]={"contacts":contact_shadows,"detail":surface_detail,"steps":contact_steps,"reach_m":.025,"bias_m":.0003,"recovery_surface_bytes":RECOVERY_CAPACITY*32}
    return result
func _capture() -> void:
    super._capture()
    _mutex.lock();_readback["passes"]=pass_profile.snapshot();_mutex.unlock()
