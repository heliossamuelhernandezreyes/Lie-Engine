extends "res://lie_wall05_android_lab.gd"
const AlignedEffect=preload("res://lie_wall06_shared_effect.gd")
const AlignedTransport=preload("res://lie_wall06_optical_transport.gd")
func _coded_source() -> String:return "res://captures/liewall06/light-model.json"
func _coded_effect_factory() -> CompositorEffect:return AlignedEffect.new(720)
func _transport_factory() -> CompositorEffect:return AlignedTransport.new()
func _ui() -> void:
    super._ui()
    for layer in get_children():
        if layer is CanvasLayer:
            for item in layer.get_children():
                if item is Label and item.text.begins_with("LIE ·"):item.text="LIE · Pared orientada · 0.3.0"
func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot()
    result["rigid_scan_alignment"]=effect.catalog.get("wall06",{}) if effect!=null else {}
    return result
