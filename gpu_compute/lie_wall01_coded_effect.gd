extends "res://lie33_tiled_hd_effect.gd"
## The LIE11 PRE_OPAQUE light code transport produces a persistent RGBA32F
## irradiance texture. This LIE33 POST_TRANSPARENT compositor consumes that
## exact source plus the original LIE11 material patch-code storage buffer.
## No CPU readback and NO second light equation for diffuse transport.
const CodedShader=preload("res://shaders/lie_wall01_coded.glsl")
var transport: CompositorEffect
var transport_bound: bool=false

func capture_root() -> String:return "res://captures/liewall01/"
func shader_resource() -> RDShaderFile:return CodedShader

func _initialize() -> bool:
    if transport==null or not transport.get("gpu_ready"):
        failure="Esperando energía codificada de LIE11"
        return false
    return super._initialize()

func _make_set() -> void:
    if _set.is_valid():_rd.free_rid(_set)
    _set=RID()
    if transport==null or not transport.get("gpu_ready"):
        failure="Missing LIE11 GPU light codes"
        return
    var irradiance_rid: RID=transport.get("output_rid")
    var material_rid: RID=transport.call("material_codes_rid")
    if not irradiance_rid.is_valid() or not material_rid.is_valid():
        failure="LIE11 coded light bindings are invalid"
        return
    var uniforms: Array[RDUniform]=[]
    for binding in _buffers:uniforms.append(_uniform(binding,_buffers[binding]))
    for binding in _images:uniforms.append(_uniform(binding,_images[binding],true))
    uniforms.append(_uniform(14,irradiance_rid,true))
    uniforms.append(_uniform(15,material_rid))
    _set=_rd.uniform_set_create(uniforms,_shader,0)
    transport_bound=_set.is_valid()

func invalidate_lighting() -> void:
    # LIE11 updates a separate persistent RGB code image; camera/geometry bytes
    # may stay identical. Force LIE33 to consume the new codes next frame.
    RenderingServer.call_on_render_thread(Callable(self,"_reset_coded_signature"))

func _reset_coded_signature() -> void:
    _resident=PackedByteArray()

func node_light_status() -> Dictionary:
    return {"transport_bound":transport_bound,
            "transport_ready":transport!=null and transport.get("gpu_ready"),
            "lighting":"LIE11 original GPU light codes -> LIE33 sampling",
            "legacy_point_light_double_counting":false}
