extends "res://lie_wall11_persistent_effect.gd"
const MaterialShader=preload("res://shaders/lie_wall12_material.glsl")
var material_response: bool=true
var bounded_raster: bool=true
var normal_filtering: bool=true
# Explicit opaque nonmetal authoring default. The common BRDF accepts F0;
# this is not a measured IOR recovered from a photograph.
const DIELECTRIC_F0: float=.04
var _appearance_control: PackedByteArray
var _gpu_appearance:=Vector3i(1,1,1)
func shader_resource() -> RDShaderFile:return MaterialShader
func _appearance_bytes(diagnostics: bool) -> PackedByteArray:
    var bytes: PackedByteArray=PackedInt32Array([1 if material_response else 0,1 if bounded_raster else 0,1 if normal_filtering else 0,0]).to_byte_array()
    bytes.resize(64);bytes.encode_float(12,DIELECTRIC_F0);bytes.encode_u32(48,1 if diagnostics else 0);return bytes
func _make_set() -> void:
    if not _buffers.has(32):
        _appearance_control=_appearance_bytes(visibility_diagnostics);_buffer(32,64,_appearance_control)
        _gpu_appearance=Vector3i(_appearance_control.decode_u32(0),_appearance_control.decode_u32(4),_appearance_control.decode_u32(8))
    super._make_set()
func set_appearance_options(material: bool,bounded: bool,filtered: bool,diagnostics: bool=false) -> void:
    if material==material_response and bounded==bounded_raster and filtered==normal_filtering and _appearance_control.size()==64 and (_appearance_control.decode_u32(48)!=0)==diagnostics:return
    var geometry_changed: bool=bounded_raster!=bounded
    material_response=material;bounded_raster=bounded;normal_filtering=filtered
    var bytes: PackedByteArray=_appearance_bytes(diagnostics);_appearance_control=bytes
    if gpu_ready:RenderingServer.call_on_render_thread(func():
        if not gpu_ready:return
        _rd.buffer_update(_buffers[32],0,16,bytes.slice(0,16));_rd.buffer_update(_buffers[32],48,4,bytes.slice(48,52))
        _gpu_appearance=Vector3i(bytes.decode_u32(0),bytes.decode_u32(4),bytes.decode_u32(8))
        if geometry_changed:_geometry_resident=PackedByteArray()
        _reset_coded_signature())
func _stage(list: int,stage: int,count: int) -> void:
    _measured_options["material_response"]=_gpu_appearance.x!=0
    _measured_options["bounded_raster"]=_gpu_appearance.y!=0
    _measured_options["normal_filtering"]=_gpu_appearance.z!=0
    super._stage(list,stage,count)
func cache_metrics() -> Dictionary:
    var result: Dictionary=super.cache_metrics()
    result["appearance"]={"material_response":material_response,"bounded_raster":bounded_raster,"normal_filtering":normal_filtering,"dielectric_f0":DIELECTRIC_F0,"scope":"opaque nonmetal direct GGX/Smith + attenuated diffuse; indirect field unchanged"};return result
func _capture() -> void:
    super._capture()
    if not gpu_ready:return
    var words: PackedInt32Array=_rd.buffer_get_data(_buffers[32]).to_int32_array()
    _mutex.lock();_readback["raster_work"]={"instrumented":words[12]!=0,"project_candidates":words[4],"raster_candidates":words[5],"project_active":words[6],"raster_active":words[7],"scope":"last geometry rebuild; counters disabled in shipping defaults"};_mutex.unlock()
