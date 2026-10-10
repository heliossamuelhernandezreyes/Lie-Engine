extends "res://lie11_light_effect.gd"
## Existing bounded transport, analytic moving box shadows, direct split.
const Rigid=preload("res://lie15_model.gd")
const DynamicShader: RDShaderFile=preload("res://shaders/lie15_transport.glsl")
var direct_rid: RID
var instance_rid: RID
var _instance_bytes:=PackedByteArray()
var _instance_pending:=PackedByteArray()

func configure_rigid(model: Dictionary,poses: Array[Transform3D]) -> bool:
    if poses.size()!=Rigid.PARTS: return false
    var data: PackedByteArray=Rigid.instance_bytes(poses,model)
    _lock.lock()
    _instance_bytes=data
    _instance_pending=data
    _lock.unlock()
    return configure(model)

func _transport_file() -> RDShaderFile:
    return DynamicShader

func _extra_transport_uniforms() -> Array[RDUniform]:
    instance_rid=_rd.storage_buffer_create(_instance_bytes.size(),_instance_bytes)
    var format:=RDTextureFormat.new()
    format.width=_count
    format.height=1
    format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
    direct_rid=_rd.texture_create(format,RDTextureView.new(),[])
    allocation_bytes+=_instance_bytes.size()+_count*16
    return [_uniform(14,instance_rid),_uniform(15,direct_rid,true)]

func _render_callback(kind: int,render_data: RenderData) -> void:
    _lock.lock()
    var data: PackedByteArray=_instance_pending
    _instance_pending=PackedByteArray()
    _lock.unlock()
    if gpu_ready and not data.is_empty(): _rd.buffer_update(instance_rid,0,data.size(),data)
    super._render_callback(kind,render_data)

func _release_gpu() -> void:
    if _rd!=null:
        # Free uniform sets in base before their backing resources.
        super._release_gpu()
        if direct_rid.is_valid(): _rd.free_rid(direct_rid)
        if instance_rid.is_valid(): _rd.free_rid(instance_rid)
