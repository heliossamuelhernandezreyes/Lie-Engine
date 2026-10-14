extends "res://lie11_light_effect.gd"
## Same radiometry/material/depth contract; receiver-CSR factors and idle reuse.
const SparseShader: RDShaderFile=preload("res://shaders/lie11_light_transport_sparse.glsl")
var _factor_geometry:=PackedByteArray()
var _factor_packet:=PackedByteArray()
var factor_builds: int=0
var factor_reuses: int=0

func _init() -> void:
    super._init();cache_static_transport=true;profile_transport=true

func _transport_file() -> RDShaderFile:
    return SparseShader

func factor_input_bytes(model: Dictionary) -> PackedByteArray:
    var key: PackedByteArray=Model.transfer_geometry_key(model)
    if key==_factor_geometry and not _factor_packet.is_empty():
        factor_reuses+=1;return _factor_packet
    var packet: PackedByteArray=Model.sparse_factor_bytes(Model.factor_bytes(model),model["patches"].size())
    if packet.is_empty():return packet
    _factor_geometry=key;_factor_packet=packet;factor_builds+=1
    return packet
