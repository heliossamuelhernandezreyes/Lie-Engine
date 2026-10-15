extends "res://lie_light_field_transport.gd"
## Common GPU-only direct/indirect bridge. Borrowed RID lives with this effect.
const SurfaceShader=preload("res://shaders/lie_surface_light.glsl")
var _surface_codes:=RID()
func _transport_file() -> RDShaderFile:return SurfaceShader
func _extra_transport_uniforms() -> Array[RDUniform]:
    var result: Array[RDUniform]=super._extra_transport_uniforms()
    var bytes:=PackedByteArray();bytes.resize(272+_count*MAX_FIELD_LIGHTS*16)
    _surface_codes=_rd.storage_buffer_create(bytes.size(),bytes)
    allocation_bytes+=bytes.size();result.append(_uniform(25,_surface_codes));return result
func _dispatch(commands: int,stage: int,threads: int,ping: int=0) -> void:
    # Stage 1 already normalized all direct emitter budgets. Export before
    # stage 2/bounces; it also works with legacy merged directions disabled.
    if stage==2:super._dispatch(commands,6,_count*_light_count,ping)
    super._dispatch(commands,stage,threads,ping)
func surface_light_codes_rid() -> RID:return _surface_codes if gpu_ready else RID()
func _release_gpu() -> void:
    super._release_gpu()
    if _surface_codes.is_valid():_rd.free_rid(_surface_codes)
    _surface_codes=RID()
