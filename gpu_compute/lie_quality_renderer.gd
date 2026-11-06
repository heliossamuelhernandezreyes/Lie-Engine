extends "res://lie_direct_renderer.gd"
const QualityLight=preload("res://shaders/lie_quality_direct_light.glsl")
func _light_shader_resource() -> RDShaderFile:return QualityLight
func _fine_visibility_flags() -> int:return 1
func _extra_light_uniforms(transport: CompositorEffect) -> Array[RDUniform]:
    return [_uniform(13,transport.quality_codes_rid())]
