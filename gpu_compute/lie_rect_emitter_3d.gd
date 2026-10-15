extends "res://lie_point_emitter_3d.gd"
@export var area_enabled: bool=false
@export var size_m:=Vector2(.30,.225)
func area_code(world: Transform3D) -> Dictionary:
    var relative: Basis=world.basis.inverse()*global_basis
    if not relative.is_finite() or not relative.is_equal_approx(relative.orthonormalized()) or relative.determinant()<0.:return {}
    return {"type":"rectangle","size":size_m,"u":relative.x,"v":relative.y,"n":-relative.z}
