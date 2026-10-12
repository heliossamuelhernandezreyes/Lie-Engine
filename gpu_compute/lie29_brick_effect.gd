extends "res://lie28_building_effect.gd"
## Preserve LIE28 immutable capture bank and original 80-byte sample format.
const BrickShader=preload("res://shaders/lie29_bricks.glsl")
func shader_resource() -> RDShaderFile:return BrickShader
