extends "res://lie_light_world.gd"
const Codes=preload("res://lie_area_emitter_codes.gd")
const Rect=preload("res://lie_rect_emitter_3d.gd")
var _shapes: Dictionary={}
var _shape_dirty: bool=false
func _validate_emitter_set(incoming: Dictionary) -> bool:
    if not super._validate_emitter_set(incoming):return false
    var candidate: Dictionary={}
    for child in get_children():
        if child is Rect and child.area_enabled:
            var shape: Dictionary=child.area_code(global_transform)
            if not Codes.valid_shape(shape):return false
            candidate[child.light_id]=shape
    var snapshot: Dictionary={"ids":incoming.keys(),"lights":incoming.values()}
    if Codes.compile(snapshot,candidate).is_empty():return false
    _shape_dirty=candidate!=_shapes;_shapes=candidate;return true
func _extra_codes_changed() -> bool:
    var dirty: bool=_shape_dirty;_shape_dirty=false;return dirty
func render_snapshot() -> Dictionary:return Codes.compile(registry.snapshot(),_shapes)
