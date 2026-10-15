extends "res://lie_wall14_android_lab.gd"
const ActiveEffect=preload("res://lie_wall15_active_effect.gd")
func _ready() -> void:
    state["active_visibility"]=true;state["precomputed_ray_boxes"]=true;state["cpu_reuse"]=true
    super._ready()
func _coded_effect_factory() -> CompositorEffect:return ActiveEffect.new(720)
func _instance_cache_identity() -> PackedByteArray:
    if not state.get("cpu_reuse",true) or effect==null:return PackedByteArray()
    return ("lie-immutable-wall/1|"+str(effect.catalog.get("sha256",""))).to_utf8_buffer()
func _apply() -> void:
    reuse_light_preparation=bool(state.get("cpu_reuse",true))
    if effect!=null:effect.cache_configure_packets=reuse_light_preparation
    if effect!=null:effect.set_work_options(bool(state.get("active_visibility",true)),bool(state.get("precomputed_ray_boxes",true)))
    super._apply()
func _cpu_stage(name: String,begin: int) -> void:
    super._cpu_stage(name,begin)
    cpu_stage_rows[-1]["cpu_reuse"]=bool(state.get("cpu_reuse",true))
func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("values",{}) is Dictionary:
        var values: Dictionary=request.get("values",{})
        for key in ["active_visibility","precomputed_ray_boxes","cpu_reuse"]:
            if values.has(key) and not values[key] is bool:return {"ok":false,"error":key+"_type","revision":revision}
    return super.command(request)
func _build_report() -> Dictionary:
    var result: Dictionary=super._build_report();result["app_version"]="1.2.0-active-visibility"
    var stages: Dictionary={};var groups: Dictionary={}
    for row in cpu_stage_rows:
        var key: String=str(row["revision"])+"|"+row["stage"]+"|"+str(row.get("cpu_reuse",true))
        if not groups.has(key):groups[key]={"stage":row["stage"],"reuse":row.get("cpu_reuse",true),"ms":0.}
        groups[key]["ms"]+=row["ms"]
    for group in groups.values():
        var key: String=group["stage"]+"|reuse="+str(group["reuse"])
        if not stages.has(key):stages[key]=[]
        stages[key].append(group["ms"])
    var summary: Dictionary={}
    for key in stages:summary[key]=Diagnostics.percentiles(stages[key])
    result["cpu_stages"]={"by_revision":summary,"rows":cpu_stage_rows.duplicate(true),"instance_cache":instance_packets.metrics(),"light_model_deep_copies":light_model_copies,"light_packet_updates":light_packet_updates,"scope":"subsets of command CPU time; do not add them again to whole-command time"}
    result["optimization_controls"]={"cpu_reuse":state["cpu_reuse"],"active_visibility":state["active_visibility"],"precomputed_ray_boxes":state["precomputed_ray_boxes"]}
    return result
func _report_header(report: Dictionary) -> String:
    return super._report_header(report).replace("LIE 1.1","LIE 1.2")
func _ui() -> void:
    super._ui();var box: Node=status.get_parent()
    _label(box,"EFICIENCIA · COMPARACIÓN",19)
    _check(box,"cpu_reuse","Reutilizar preparación CPU")
    _check(box,"active_visibility","Consultar superficies visibles")
    _check(box,"precomputed_ray_boxes","Acelerar recorrido de sombras")
    for item in picture.get_parent().get_children():
        if item is Label and item.text.begins_with("LIE ·"):item.text="LIE · Superficies activas · 1.2.0"
func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot()
    for key in ["active_visibility","precomputed_ray_boxes","cpu_reuse"]:result["control_contract"]["booleans"].append(key)
    result["cpu_instance_cache"]=instance_packets.metrics()
    return result
