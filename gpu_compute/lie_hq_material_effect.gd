extends "res://lie_scanned_masonry_effect.gd"
var bank_name: String="concrete_layers"
func capture_root() -> String:return "res://captures/hq_materials/"+bank_name+"/"
func instance_capacity() -> int:return 16
func work_capacity() -> int:return 750000
func _init(material_name: String="concrete_layers",size: int=1024) -> void:
    bank_name=material_name
    super._init(720)
    output_size=clampi(size,256,1024);render_size=output_size*2
