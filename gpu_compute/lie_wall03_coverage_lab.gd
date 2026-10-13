extends "res://lie_wall02_coded_lab.gd"
## Genuine 96-brick scan + original LIE11 transport, extra mortar codes and
## bounded interior coverage repair. No additional visible source polygons.
const CoverageEffect=preload("res://lie_wall03_coverage_effect.gd")

func _ready() -> void:
    state["coverage_enabled"]=true
    super._ready()

func _coded_source() -> String:
    return "res://captures/liewall03/light-model.json"

func _coded_effect_factory() -> CompositorEffect:
    return CoverageEffect.new(1080)

func _lab_heading() -> String:
    return "LIE-WALL-03 · Escaneo real · Cobertura y mortero por nodos"

func _lab_geometry_text() -> String:
    return "96 ladrillos escaneados · 1 caja invisible\nSin mallas visibles · 3 LOD reales\nReparación de huecos SOLO dentro del ladrillo\nJuntas rehundidas con 8 nodos RGB independientes"

func _lab_source_text() -> String:
    return "LIE11: 872 nodos, absorción y 2 rebotes\n96 proxies de sombra únicamente GPU\nLIE33: relleno condicionado por normal/profundidad\nColor fotográfico del escaneo sin retexturizar"

func _extra_light_controls(parent: VBoxContainer) -> void:
    super._extra_light_controls(parent)
    _check(parent,"coverage_enabled","Cobertura interior segura · ON/OFF")

func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("values",{}) is Dictionary:
        var values: Dictionary=request["values"]
        if values.has("coverage_enabled") and not values["coverage_enabled"] is bool:
            return {"ok":false,"error":"coverage_boolean","revision":revision}
    return super.command(request)

func _apply() -> void:
    if effect!=null and effect.has_method("set_coverage_enabled"):
        effect.call("set_coverage_enabled",bool(state.get("coverage_enabled",true)))
    super._apply()

func agent_snapshot() -> Dictionary:
    var info: Dictionary=super.agent_snapshot()
    info["coverage_active"]=bool(state.get("coverage_enabled",true))
    info["material_light_nodes"]=light_model.get("patches",[]).size()
    info["mortar_light_nodes"]=8
    info["coverage_profiler"]=effect.call("coverage_profile") if effect!=null else {}
    info["renderer"]="Original LIE11 code injection → LIE33 scan splats + enclosed-hole recovery"
    return info
