extends "res://lie_wall08_android_lab.gd"
const SurfaceTransport=preload("res://lie_wall09_surface_transport.gd")
const SurfaceEffect=preload("res://lie_wall09_shared_effect.gd")
func _ready() -> void:
    state["contact_shadows"]=true;state["surface_detail"]=true;state["contact_steps"]=12
    super._ready()
func _transport_factory() -> CompositorEffect:return SurfaceTransport.new()
func _coded_effect_factory() -> CompositorEffect:return SurfaceEffect.new(720)
func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("values",{}) is Dictionary:
        var values: Dictionary=request.get("values",{})
        for key in ["contact_shadows","surface_detail"]:
            if values.has(key) and not values[key] is bool:return {"ok":false,"error":key+"_type","revision":revision}
        if values.has("contact_steps"):
            var value: Variant=values["contact_steps"]
            if not value is int:return {"ok":false,"error":"contact_steps_type","revision":revision}
            if value<4 or value>32:return {"ok":false,"error":"contact_steps_range","revision":revision}
    return super.command(request)
func _apply() -> void:
    if effect!=null:effect.set_surface_options(bool(state["contact_shadows"]),bool(state["surface_detail"]),int(state["contact_steps"]))
    super._apply()
func _ui() -> void:
    super._ui();var box: Node=status.get_parent()
    _label(box,"RELIEVE Y CONTACTO",19)
    _check(box,"surface_detail","Luz según el relieve capturado")
    _check(box,"contact_shadows","Sombras cortas de contacto")
    _label(box,"Pasos de contacto",17)
    var slider:=HSlider.new();slider.min_value=4;slider.max_value=32;slider.step=1;slider.value=12;slider.custom_minimum_size=Vector2(270,34)
    slider.value_changed.connect(func(v: float):command({"op":"set_values","values":{"contact_steps":int(v)}}))
    box.add_child(slider);controls["contact_steps"]=slider
    for layer in get_children():
        if layer is CanvasLayer:
            for item in layer.get_children():
                if item is Label and item.text.begins_with("LIE ·"):item.text="LIE · Relieve y contacto · 0.6.0"
func _process(delta: float) -> void:
    var previous_report: int=_report_clock;super._process(delta)
    if previous_report==_report_clock or status==null or effect==null:return
    var profile: Dictionary=effect.pass_profile.snapshot()
    if not profile["available"]:
        status.text+="\nGPU por pasada: esperando medición";return
    for name in ["project","raster","recovery_reuse","surface_light","output"]:
        if profile["passes"].has(name):
            var row: Dictionary=profile["passes"][name]
            var title: String={"project":"Proyección","raster":"Profundidad","recovery_reuse":"Recuperación","surface_light":"Relieve/contacto","output":"Salida"}[name]
            status.text+="\n%s: %.2f ms · p95 %.2f (%d)" % [title,row["p50_ms"],row["p95_ms"],row["samples"]]
    status.text+="\nMediciones de cambios; imagen quieta en caché"
func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot()
    for key in ["contact_shadows","surface_detail"]:
        if not result["control_contract"]["booleans"].has(key):result["control_contract"]["booleans"].append(key)
    result["control_contract"]["limits"]["contact_steps"]=[4,32]
    result["gpu_passes"]=effect.pass_profile.snapshot() if effect!=null else {}
    return result
