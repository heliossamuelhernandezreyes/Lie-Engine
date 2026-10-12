extends "res://lie31_hd_effect.gd"
## Full-HD-height **square** native compositor. NOT 1920x1080 widescreen.
## LIE22 clamps to 512, so extend inherited buffer dimensions before first GPU init.
func _init(size: int=1080) -> void:
    super._init(512)
    output_size=clampi(size,720,1080)
    render_size=output_size*2
