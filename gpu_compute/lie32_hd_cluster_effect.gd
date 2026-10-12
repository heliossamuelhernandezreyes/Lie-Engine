extends "res://lie32_cluster_effect.gd"
## True square native 960px LIE32 compositing; Vulkan workgroups fit 57,600 < 65,535.
func _init(size: int=960) -> void:
    super._init(512)
    output_size=clampi(size,720,960)
    render_size=output_size*2
