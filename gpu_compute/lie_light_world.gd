extends Node3D
## Main-thread scene snapshot -> immutable light codes -> render-thread GPU.
signal codes_changed(snapshot: Dictionary)
const Registry=preload("res://lie_light_registry.gd")
const Emitter=preload("res://lie_point_emitter_3d.gd")
var registry=Registry.new()
func _process(_delta: float) -> void:refresh()
func refresh() -> bool:
    # Preserve meter units. A world transform may translate/rotate, not scale.
    var basis: Basis=global_basis
    if not basis.is_finite() or not basis.is_equal_approx(basis.orthonormalized()) or basis.determinant()<0.:return false
    var incoming: Dictionary={}
    for child in get_children():
        if not child is Emitter:continue
        var id: String=child.light_id
        if id.is_empty() or id.length()>96 or incoming.has(id):return false
        var code: Dictionary=child.light_code(global_transform)
        if not Registry.Model.valid_light_codes([code]):return false
        for key in code:
            if key not in ["position","power_rgb","radius"]:return false
        incoming[id]=code
    if incoming.size()>Registry.CAPACITY:return false
    var before: int=registry.revision
    for id in registry.snapshot()["ids"]:
        if id!="" and not incoming.has(id):registry.remove(id)
    for id in incoming:
        if not registry.upsert(id,incoming[id]):return false
    if registry.revision!=before:codes_changed.emit(registry.snapshot())
    return true
