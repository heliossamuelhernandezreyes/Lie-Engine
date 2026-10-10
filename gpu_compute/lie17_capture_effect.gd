extends "res://lie16_capture_effect.gd"
## Optional contrast-guided edge reconstruction; same capture/lighting buffers.
const EdgeComposite: RDShaderFile=preload("res://shaders/lie17_composite.glsl")

func _init(size: int=384) -> void:
    super(size)
    edge_aa_enabled=true

func composite_file() -> RDShaderFile:
    return EdgeComposite
