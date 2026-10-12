extends "res://lie31_hd_effect.gd"
## Full-HD-height **square** native compositor. NOT 1920x960 widescreen.
## LIE22 clamps to 512, so extend inherited buffer dimensions before first GPU init.
func _init(size: int=960) -> void:
    super._init(512)
    output_size=clampi(size,720,960)
    render_size=output_size*2
