extends "res://lie28_building_effect.gd"
## Captured camera + shared resident transport. Original meshes stay offline.
const BenchShader=preload("res://shaders/lie_brick_reference.glsl")
var transport: CompositorEffect
var bench_packet:=PackedByteArray()
func capture_root() -> String:return "res://captures/brick_reference/"
func shader_resource() -> RDShaderFile:return BenchShader
func _buffer(binding: int,length: int,data: PackedByteArray=PackedByteArray()) -> void:
    super._buffer(binding,length*8 if binding==13 else length,data)
func _make_set() -> void:
    if not _buffers.has(14):_buffer(14,bench_packet.size(),bench_packet)
    if _set.is_valid():_rd.free_rid(_set)
    var uniforms: Array[RDUniform]=[]
    for binding in _buffers:uniforms.append(_uniform(binding,_buffers[binding]))
    for binding in _images:uniforms.append(_uniform(binding,_images[binding],true))
    uniforms.append(_uniform(15,transport.output_rid,true))
    uniforms.append(_uniform(16,transport.surface_light_codes_rid()))
    uniforms.append(_uniform(18,transport.emission_descriptors_rid()))
    _set=_rd.uniform_set_create(uniforms,_shader,0)
func _render_callback(kind: int,data: RenderData) -> void:
    if transport==null or not transport.gpu_ready:return
    _mutex.lock()
    if _pending.has("parameters"):_pending.parameters.encode_float(248,float(transport.frame_count))
    _mutex.unlock()
    super._render_callback(kind,data)
