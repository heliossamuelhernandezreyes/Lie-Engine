extends "res://lie28_building_effect.gd"
# Reuse LIE native capture compositor with genuine verified WALL04 source surfaces.
const HouseShader=preload("res://shaders/lie36_house_material.glsl")
func shader_resource() -> RDShaderFile:return HouseShader
func capture_root() -> String:return "res://captures/liehouse36/"
