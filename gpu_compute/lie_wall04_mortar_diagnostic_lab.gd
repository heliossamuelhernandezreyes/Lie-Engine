extends "res://lie_wall04_mortar_lab.gd"
const CoverageDiagnosticEffect=preload("res://lie_wall04_mortar_diagnostic_effect.gd")
func _coded_effect_factory() -> CompositorEffect:
    return CoverageDiagnosticEffect.new(1080)
func _lab_heading() -> String:
    return "LIE-WALL-04 Diagnóstico · Verde = mortero efectivamente renderizado"
