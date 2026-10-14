extends "res://lie_wall02_micro_transport.gd"
## Same LIE11 real RGB flux, source patches, two bounces, 96 light-only boxes.
## WALL04-specific physics fix: a patch INSIDE the coarse opaque wall core
## cannot shadow itself when casting a direct-ray toward the real light.
const WALL04_TRANSPORT: RDShaderFile=preload("res://shaders/lie_wall04_transport.glsl")
func _transport_file() -> RDShaderFile:
    return WALL04_TRANSPORT
