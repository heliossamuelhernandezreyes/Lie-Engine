extends "res://lie29_brick_effect.gd"
## Three real captured masters, one shared immutable GPU buffer.
const MasonryShader=preload("res://shaders/lie30_masonry.glsl")
func capture_root() -> String:return "res://captures/lie30masonry/"
func shader_resource() -> RDShaderFile:return MasonryShader
