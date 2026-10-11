extends "res://lie23_face_lab.gd"
const ModularDoc=preload("res://workshop/lie_modular_face_document.gd")
var nose_picker: OptionButton
var random_seed: int=17
func _create_effect() -> CompositorEffect:
    return FaceEffect.new(512,2,"res://captures/face24/")
func _directory() -> String:
    return "user://face24"
func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot();result["commands"].append("randomize")
    result["facial_family"]="lee-face-v1";result["nose_choices"]=[0,1,2,3];return result
func _ready() -> void:
    document=ModularDoc.new();super._ready();get_window().size=Vector2i(1280,900)
func _build_ui() -> void:
    super._build_ui()
    var left: VBoxContainer=controls["head_yaw"].get_parent()
    var label: Label=_label(left,"CONSTRUCCIÓN FACIAL · NARIZ")
    nose_picker=OptionButton.new()
    for title in ["Base sin nariz","Clásica","Corta","Ancha"]:nose_picker.add_item(title)
    left.add_child(nose_picker);left.move_child(label,2);left.move_child(nose_picker,3)
    nose_picker.item_selected.connect(func(index: int):command({"op":"set_values","values":{"nose_index":index}}))
    _button(left,"Variar nariz · misma familia",func():command({"op":"randomize","seed":random_seed});random_seed+=1)
    for child in ui.get_children():
        if child is Label and child.text.begins_with("LIE  ·"):child.text="LIE  ·  Construcción facial modular"
func _refresh() -> void:
    super._refresh()
    if nose_picker!=null:nose_picker.select(int(document.state["nose_index"]))
func _apply() -> void:
    super._apply()
    if effect!=null and effect.get("capture_loaded"):
        var m: Dictionary=effect.get("master")
        if stats!=null:stats.text="%d vértices de control · antes %d\n%d muestras rígidas sin malla densa\nUna base · tres narices · ojos compartidos"%[m["vertex_count"],m["original_vertex_count"],m["rigid_face_sample_count"]]
