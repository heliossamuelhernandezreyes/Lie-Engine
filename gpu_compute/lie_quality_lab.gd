extends "res://lie_direct_views_lab.gd"
const QualityTransport=preload("res://lie_wall_quality_transport.gd")
const QualityEffect=preload("res://lie_quality_effect.gd")
const QualityModel=preload("res://lie_field_quality_model.gd")
func _transport_factory() -> CompositorEffect:return QualityTransport.new()
func _coded_effect_factory() -> CompositorEffect:return QualityEffect.new(720)
func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("op")=="field_policy":
        var options: Variant=request.get("options")
        if not QualityModel.valid(options):return {"ok":false,"error":"field_policy","revision":revision}
        if transport==null or not transport.set_field_quality(options):return {"ok":false,"error":"field_policy_state","revision":revision}
        effect.invalidate_lighting();revision+=1
        return {"ok":true,"revision":revision,"quality":transport.optical_metrics().quality}
    if request is Dictionary and request.get("op")=="light_occluders":
        if not request.get("boxes") is Array or not request.get("expected_revision") is int or not request.get("new_revision") is int:
            return {"ok":false,"error":"occluder_transaction","revision":revision}
        if transport==null or not transport.set_dynamic_occluders(request.boxes,request.expected_revision,request.new_revision):
            return {"ok":false,"error":"occluder_revision_or_bounds","revision":revision}
        effect.invalidate_lighting();revision+=1
        return {"ok":true,"revision":revision,"quality":transport.optical_metrics().quality}
    return super.command(request)
func _ui() -> void:
    super._ui()
    var box: Node=status.get_parent()
    _label(box,"ILUMINACIÓN POR SUPERFICIES",19)
    var radius_button:=CheckButton.new();radius_button.text="Radio energético";radius_button.button_pressed=state.get("energy_radius",false)
    radius_button.toggled.connect(func(v: bool):command({"op":"set_values","values":{"energy_radius":v}}));box.add_child(radius_button)
    var old:=Button.new();old.text="Comparar transporte anterior"
    old.pressed.connect(func():command({"op":"field_policy","options":{"angular_sectors":1,"area_budget":false}}));box.add_child(old)
    var improved:=Button.new();improved.text="Usar transporte mejorado"
    improved.pressed.connect(func():command({"op":"field_policy","options":{"angular_sectors":6,"area_budget":true}}));box.add_child(improved)
