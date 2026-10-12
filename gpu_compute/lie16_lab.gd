extends "res://lie15_lab.gd"
const Quality=preload("res://lie16_capture_effect.gd")
var _quality_mode: String="Equilibrado"

func make_capture() -> CompositorEffect:
    return Quality.new()

func apply_pose() -> void:
    super.apply_pose()
    if effect!=null and not model.is_empty():
        effect.call("set_lighting_signature",JSON.stringify([model["lights"],model["bounces"],model["surface_materials"]]))

func set_reference(value: bool) -> void:
    if effect!=null: effect.call("reset_history")
    super.set_reference(value)

func _build_ui() -> void:
    super._build_ui()
    var panel: VBoxContainer=ui.get_child(0) as VBoxContainer
    var choice:=OptionButton.new()
    for mode in ["Equilibrado","Detalle completo","Sin historial"]: choice.add_item(mode)
    choice.item_selected.connect(func(index: int):
        _quality_mode=choice.get_item_text(index)
        effect.call("configure_quality",index!=1,index!=2,true,index!=2))
    panel.add_child(choice)
    var hint:=Label.new()
    hint.text="Calidad adaptable · bordes suaves\nHistorial con profundidad y articulaciones"
    panel.add_child(hint)
