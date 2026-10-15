extends Node3D
## Main-thread scene snapshot -> immutable light codes -> render-thread GPU.
signal codes_changed(snapshot: Dictionary)
const Registry=preload("res://lie_light_registry.gd")
const Emitter=preload("res://lie_point_emitter_3d.gd")
var registry=Registry.new()
var _update_depth: int=0
func begin_update() -> void:_update_depth+=1
func end_update() -> bool:
    if _update_depth<=0:return false
    _update_depth-=1
    return refresh() if _update_depth==0 else true
func _validate_emitter_set(incoming: Dictionary) -> bool:return incoming.size()<=Registry.CAPACITY
func _extra_codes_changed() -> bool:return false
func render_snapshot() -> Dictionary:return registry.snapshot()
func _process(_delta: float) -> void:refresh()
func refresh() -> bool:
    if _update_depth>0:return true
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
    if not _validate_emitter_set(incoming):return false
    var before: int=registry.revision
    for id in registry.snapshot()["ids"]:
        if id!="" and not incoming.has(id):registry.remove(id)
    for id in incoming:
        if not registry.upsert(id,incoming[id]):return false
    var extra: bool=_extra_codes_changed()
    if registry.revision!=before or extra:codes_changed.emit(render_snapshot())
    return true
