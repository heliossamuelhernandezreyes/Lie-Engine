extends "res://lie_wall11_android_lab.gd"
const MaterialEffect=preload("res://lie_wall12_material_effect.gd")
func _ready() -> void:
    state["material_response"]=true;state["bounded_raster"]=true;state["normal_filtering"]=true
    super._ready()
func _coded_effect_factory() -> CompositorEffect:return MaterialEffect.new(720)
func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("values",{}) is Dictionary:
        for key in ["material_response","bounded_raster","normal_filtering"]:
            if request["values"].has(key) and not request["values"][key] is bool:return {"ok":false,"error":key+"_type","revision":revision}
    return super.command(request)
func _apply() -> void:
    if effect!=null:effect.set_appearance_options(bool(state["material_response"]),bool(state["bounded_raster"]),bool(state["normal_filtering"]),bool(state.get("visibility_diagnostics",false)))
    super._apply()
func _ui() -> void:
    super._ui();var box: Node=status.get_parent()
    _label(box,"MATERIAL E ILUMINACIÓN",19)
    _check(box,"material_response","Respuesta óptica del material")
    _check(box,"normal_filtering","Estabilizar microbrillos")
    _check(box,"bounded_raster","Acotar trabajo a la huella visible")
    _label(box,"La respuesta óptica usa Luz según el relieve.\nLa rugosidad procede del asset capturado.",15)
    for layer in get_children():
        if layer is CanvasLayer:
            for item in layer.get_children():
                if item is Label and item.text.begins_with("LIE ·"):item.text="LIE · Material y eficiencia · 0.9.0"
func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot()
    for key in ["material_response","bounded_raster","normal_filtering"]:
        if not result["control_contract"]["booleans"].has(key):result["control_contract"]["booleans"].append(key)
    result["control_contract"]["appearance"]={"requires_surface_detail":true,"opaque_nonmetal":true,"dielectric_f0":effect.DIELECTRIC_F0,"measured_material":false}
    return result
