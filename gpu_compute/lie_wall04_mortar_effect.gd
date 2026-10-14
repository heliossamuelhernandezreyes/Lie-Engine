extends "res://lie_wall03_coverage_effect.gd"
## Experimental source-photographed mortar. The inherited 872-node LIE11
## transport, stable 80-byte records and ONLY the parent spatial envelope
## remain unchanged. The new shader entirely forbids analytic flat mortar.
const PhotographicMortarShader: RDShaderFile=preload("res://shaders/lie_wall04_mortar.glsl")

func capture_root() -> String:
    return "res://captures/liewall04/"

func shader_resource() -> RDShaderFile:
    return PhotographicMortarShader
