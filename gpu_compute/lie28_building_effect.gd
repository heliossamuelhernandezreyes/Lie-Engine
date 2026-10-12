extends "res://lie22_modular_effect.gd"
const BuildingShader=preload("res://shaders/lie28_building.glsl")
func capture_root() -> String:return "res://captures/building28/"
func sample_stride() -> int:return 80
func shader_resource() -> RDShaderFile:return BuildingShader
