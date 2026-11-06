extends "res://lie_direct_views_lab.gd"
const QualityTransport=preload("res://lie_wall_quality_transport.gd")
const QualityEffect=preload("res://lie_quality_effect.gd")
const QualityModel=preload("res://lie_field_quality_model.gd")
func _transport_factory() -> CompositorEffect:return QualityTransport.new()
func _coded_effect_factory() -> CompositorEffect:return QualityEffect.new(720)
func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("values",{}) is Dictionary:
        for key in ["separate_lights","optical_codes"]:
            if request.get("values",{}).has(key) and request.values[key]!=true:return {"ok":false,"error":"quality_requires_source_directions","revision":revision}
    if request is Dictionary and request.get("op")=="field_policy":
        var options: Variant=request.get("options")
        if not QualityModel.valid(options):return {"ok":false,"error":"field_policy","revision":revision}
        if transport==null or not transport.set_field_quality(options):return {"ok":false,"error":"field_policy_state","revision":revision}
        effect.invalidate_lighting();revision+=1
        return {"ok":true,"revision":revision,"quality":transport.optical_metrics().quality}
    if request is Dictionary and request.get("op")=="light_occluders":
        if not request.get("boxes") is Array or not QualityModel.integer_value(request.get("expected_revision"),0,0xffffffff) or not QualityModel.integer_value(request.get("new_revision"),0,0xffffffff):
            return {"ok":false,"error":"occluder_transaction","revision":revision}
        if transport==null or not transport.set_dynamic_occluders(request.boxes,int(request.expected_revision),int(request.new_revision)):
            return {"ok":false,"error":"occluder_revision_or_bounds","revision":revision}
        effect.invalidate_lighting();revision+=1
        return {"ok":true,"revision":revision,"quality":transport.optical_metrics().quality}
    return super.command(request)
func _quality_mode(sectors: int,budget: bool) -> void:
    if transport==null:return
    var options: Dictionary=transport.optical_metrics().quality.policy.duplicate(true)
    options.angular_sectors=sectors;options.area_budget=budget
    command({"op":"field_policy","options":options})
func _ui() -> void:
    super._ui()
    var box: Node=status.get_parent()
    _label(box,"ILUMINACIÓN POR SUPERFICIES",19)
    _check(box,"energy_radius","Radio energético")
    var old:=Button.new();old.text="Comparar transporte anterior"
    old.pressed.connect(func():_quality_mode(1,false));box.add_child(old)
    var improved:=Button.new();improved.text="Usar transporte mejorado"
    improved.pressed.connect(func():_quality_mode(6,true));box.add_child(improved)
