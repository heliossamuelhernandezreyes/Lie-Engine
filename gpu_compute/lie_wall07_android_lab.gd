extends "res://lie_wall06_android_lab.gd"
const ContinuousEffect=preload("res://lie_wall07_shared_effect.gd")
func _ready() -> void:
    state["continuous_light"]=true
    super._ready()
func _coded_effect_factory() -> CompositorEffect:return ContinuousEffect.new(720)
func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("values",{}) is Dictionary:
        var values: Dictionary=request.get("values",{})
        if values.has("continuous_light") and not values["continuous_light"] is bool:return {"ok":false,"error":"continuous_light_type","revision":revision}
    return super.command(request)
func _apply() -> void:
    if effect!=null:effect.set_continuous_light(bool(state.get("continuous_light",true)))
    super._apply()
func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot()
    if not result["control_contract"]["booleans"].has("continuous_light"):result["control_contract"]["booleans"].append("continuous_light")
    return result
func _ui() -> void:
    super._ui();_check(status.get_parent(),"continuous_light","Luz continua entre regiones")
    for layer in get_children():
        if layer is CanvasLayer:
            for item in layer.get_children():
                if item is Label and item.text.begins_with("LIE ·"):item.text="LIE · Pared · 0.4.0"
