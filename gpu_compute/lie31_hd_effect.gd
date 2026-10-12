extends "res://lie30_masonry_effect.gd"
## Derived real 4K photographic CC0 PBR brick data; 80-byte LIE sample layout.
const HdShader=preload("res://shaders/lie30_masonry.glsl")
func capture_root() -> String:return "res://captures/lie31hd/"
func shader_resource() -> RDShaderFile:return HdShader
