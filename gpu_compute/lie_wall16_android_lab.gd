extends "res://lie_wall15_android_lab.gd"
const QueryEffect=preload("res://lie_wall16_query_effect.gd")
func _ready() -> void:
    state["surface_queries"]=true;state["occlusion_witnesses"]=true;super._ready()
func _coded_effect_factory() -> CompositorEffect:return QueryEffect.new(720)
func _apply() -> void:
    if effect!=null:effect.set_query_options(bool(state.get("surface_queries",true)),bool(state.get("occlusion_witnesses",true)))
    super._apply()
func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("values",{}) is Dictionary:
        for key in ["surface_queries","occlusion_witnesses"]:
            if request.get("values",{}).has(key) and not request["values"][key] is bool:return {"ok":false,"error":key+"_type","revision":revision}
    return super.command(request)
func _build_report() -> Dictionary:
    var result: Dictionary=super._build_report();result["app_version"]="1.3.0-surface-queries"
    for key in ["surface_queries","occlusion_witnesses"]:result["optimization_controls"][key]=state[key]
    return result
func _portable_report(report: Dictionary) -> Dictionary:
    var result: Dictionary=super._portable_report(report)
    result["cache"]["surface_queries"]=report["cache"]["surface_queries"]
    return result
func _report_header(report: Dictionary) -> String:return super._report_header(report).replace("LIE 1.2","LIE 1.3")
func _ui() -> void:
    super._ui();var box: Node=status.get_parent()
    _label(box,"SUPERFICIES · COMPARACIÓN",19)
    _check(box,"surface_queries","Seleccionar antes de proyectar")
    _check(box,"occlusion_witnesses","Revalidar obstáculos de sombra")
    for item in picture.get_parent().get_children():
        if item is Label and item.text.begins_with("LIE ·"):item.text="LIE · Consultas de superficie · 1.3.0"
func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot()
    for key in ["surface_queries","occlusion_witnesses"]:result["control_contract"]["booleans"].append(key)
    return result
