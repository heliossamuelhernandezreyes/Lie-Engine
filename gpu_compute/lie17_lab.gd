extends "res://lie16_lab.gd"
const EdgeQuality=preload("res://lie17_capture_effect.gd")

func make_capture() -> CompositorEffect:
    return EdgeQuality.new()

func _build_ui() -> void:
    super._build_ui()
    var toggle:=CheckBox.new()
    toggle.text="Suavizar bordes por contraste"
    toggle.button_pressed=true
    toggle.toggled.connect(func(value: bool): effect.call("set_edge_aa",value))
    (ui.get_child(0) as VBoxContainer).add_child(toggle)
