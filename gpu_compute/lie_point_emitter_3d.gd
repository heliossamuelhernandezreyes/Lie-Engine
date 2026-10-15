extends Node3D
## Scene source for LIE; no duplicate native PBR light is created.
@export var light_id: String=""
@export var power_rgb_linear:=Vector3(20.,12.,6.)
@export_range(.01,10000.) var radius_m: float=6.
@export var enabled: bool=true

func light_code(world: Transform3D) -> Dictionary:
    var p: Vector3=world.affine_inverse()*global_position
    var rgb: Vector3=power_rgb_linear if enabled else Vector3.ZERO
    return {"position":[p.x,p.y,p.z],"radius":radius_m,"power_rgb":[rgb.x,rgb.y,rgb.z]}
