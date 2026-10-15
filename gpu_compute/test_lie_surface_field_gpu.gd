extends "res://test_lie_light_field_gpu.gd"
const SurfaceShader=preload("res://shaders/lie_surface_light.glsl")
func shader_resource() -> RDShaderFile:return SurfaceShader
func surface_bridge() -> bool:return true
