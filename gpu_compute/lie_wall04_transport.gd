extends "res://lie_wall02_micro_transport.gd"
## Same LIE11 real RGB flux, source patches, two bounces, 96 light-only boxes.
## WALL04-specific physics fix: a patch INSIDE the coarse opaque wall core
## cannot shadow itself when casting a direct-ray toward the real light.
const WALL04_TRANSPORT: RDShaderFile=preload("res://shaders/lie_wall04_transport.glsl")
func _transport_file() -> RDShaderFile:
    return WALL04_TRANSPORT

## Replace ONLY the precomputed LIE11 indirect visibility graph. The
## legacy giant wall core incorrectly blocked physical bounce paths among
## distinct source bricks. Radiometry, powers, node code ABI and 2 bounce
## generations remain the ORIGINAL LIE11 GPU implementation.
func configure(model: Dictionary) -> bool:
    var physical: Dictionary=model.duplicate(true)
    physical["blockers"]=[] # Direct shadowing is handled by 96 scanned-brick AABBs.
    var n: int=(physical.get("patches",[]) as Array).size()
    var path: String="res://captures/liewall04/indirect_factors.bin"
    if n!=872 or not FileAccess.file_exists(path):
        failure="WALL04 872-patch source-correct indirect visibility matrix missing"
        return false
    var factors: PackedByteArray=FileAccess.get_file_as_bytes(path)
    if factors.size()!=n*n*4:
        failure="Invalid original-light transport matrix dimension"
        return false
    if not super.configure(physical):
        return false
    _lock.lock()
    _pending[2]=factors
    _lock.unlock()
    return true
