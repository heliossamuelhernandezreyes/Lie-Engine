extends "res://lie_wall09_android_lab.gd"
const SourceEffect=preload("res://lie_wall10_shared_effect.gd")
func _ready() -> void:
    state["surface_continuity"]=true;state["world_contacts"]=true
    super._ready()
func _coded_effect_factory() -> CompositorEffect:return SourceEffect.new(720)
func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("values",{}) is Dictionary:
        for key in ["surface_continuity","world_contacts"]:
            if request["values"].has(key) and not request["values"][key] is bool:return {"ok":false,"error":key+"_type","revision":revision}
    return super.command(request)
func _apply() -> void:
    if effect!=null:effect.set_surface_continuity(bool(state["surface_continuity"]));effect.set_world_contacts(bool(state["world_contacts"]))
    super._apply()
func _ui() -> void:
    super._ui();var box: Node=status.get_parent()
    _label(box,"SUPERFICIE COMPARTIDA EN 3D",19)
    _check(box,"surface_continuity","Muestras distribuidas en la superficie")
    _check(box,"world_contacts","Sombras 3D del maestro compartido")
    _label(box,"Sombras 3D: alcance 2.5 cm.\nPasos de contacto ajusta el modo en pantalla.",15)
    for layer in get_children():
        if layer is CanvasLayer:
            for item in layer.get_children():
                if item is Label and item.text.begins_with("LIE ·"):item.text="LIE · Superficie y sombras 3D · 0.7.0"
func _process(delta: float) -> void:
    var previous: int=_report_clock;super._process(delta)
    if previous==_report_clock or status==null or effect==null:return
    var profile: Dictionary=effect.pass_profile.snapshot()
    if profile["passes"].has("world_visibility"):
        var row: Dictionary=profile["passes"]["world_visibility"]
        status.text+="\nVisibilidad 3D: %.2f ms · p95 %.2f (%d)" % [row["p50_ms"],row["p95_ms"],row["samples"]]
    status.text+="\nSombras: "+("maestro 3D" if state["world_contacts"] else "pantalla")
func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot()
    for key in ["surface_continuity","world_contacts"]:
        if not result["control_contract"]["booleans"].has(key):result["control_contract"]["booleans"].append(key)
    return result
