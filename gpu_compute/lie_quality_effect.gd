extends "res://lie_direct_effect.gd"
const QualityRenderer=preload("res://lie_quality_renderer.gd")
func _direct_renderer_factory() -> RefCounted:return QualityRenderer.new()
