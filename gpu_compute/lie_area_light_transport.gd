extends "res://lie_surface_light_transport.gd"
const AreaField=preload("res://shaders/lie_area_field.glsl")
var desired_light_count: int=0
var _emission_rid:=RID()
var _emission_bytes:=PackedByteArray()
var _last_queued:=PackedByteArray()
func _transport_file() -> RDShaderFile:return AreaField
func _validated_emission(model: Dictionary) -> PackedByteArray:
    var bytes: Variant=model.get("emission_descriptors",PackedByteArray())
    if not bytes is PackedByteArray:return PackedByteArray()
    if bytes.is_empty():bytes.resize(128)
    if bytes.size()!=128:return PackedByteArray()
    for i in range(8):
        var at: int=i*16;var normal:=Vector3(bytes.decode_float(at),bytes.decode_float(at+4),bytes.decode_float(at+8));var kind: float=bytes.decode_float(at+12)
        if not normal.is_finite() or kind not in [0.,1.] or (kind==1. and (i>=model.get("lights",[]).size() or absf(normal.length_squared()-1.)>.0001)):return PackedByteArray()
    return bytes
func configure(model: Dictionary) -> bool:
    if _validated_emission(model).is_empty():return false
    if not super.configure(model):return false
    desired_light_count=model["lights"].size();return true
func set_light_codes(model: Dictionary) -> void:
    if _validated_emission(model).is_empty():return
    super.set_light_codes(model)
func _additional_transport_data(model: Dictionary) -> Dictionary:
    var bytes: PackedByteArray=_validated_emission(model);var changed: bool=bytes!=_last_queued
    _last_queued=bytes;return {"emission":bytes,"force":changed}
func _before_transport_update(data: Dictionary) -> void:
    if data.has("emission"):
        _emission_bytes=data["emission"]
        if _emission_rid.is_valid():_rd.buffer_update(_emission_rid,0,128,_emission_bytes)
func _extra_transport_uniforms() -> Array[RDUniform]:
    var result: Array[RDUniform]=super._extra_transport_uniforms()
    if _emission_bytes.is_empty():_emission_bytes.resize(128)
    _emission_rid=_rd.storage_buffer_create(128,_emission_bytes);allocation_bytes+=128
    result.append(_uniform(26,_emission_rid));return result
func emission_descriptors_rid() -> RID:return _emission_rid if gpu_ready else RID()
func _release_gpu() -> void:
    super._release_gpu()
    if _emission_rid.is_valid():_rd.free_rid(_emission_rid)
    _emission_rid=RID()
