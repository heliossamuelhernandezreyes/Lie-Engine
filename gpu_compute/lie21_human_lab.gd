extends "res://lie20_human_lab.gd"
const QualityEffect=preload("res://lie21_human_effect.gd")
var capture_root: String="res://captures/human_quality/"

func _create_effect() -> CompositorEffect:
    return QualityEffect.new(512,2,capture_root)

func _title_text() -> String:
    return "LIE  ·  Maestro humano · calidad 21"

func _caption_text() -> String:
    return "Capturas 384² · reconstrucción ponderada · antialiasing 2×"

func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot()
    result["quality"]={"capture_resolution":384,"output_resolution":512,"internal_resolution":1024,"weighted_material":true,"source_mesh_drawn":false}
    return result
