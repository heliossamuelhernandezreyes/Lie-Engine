extends "res://lie_brick01_lab.gd"
## Single physically captured master, reusable across wall instances.
const ScannedEffect=preload("res://lie_brick02_scan_effect.gd")
func _make_effect() -> CompositorEffect:return ScannedEffect.new(1080)
func _lab_heading() -> String:return "LIE-BRICK-02 · Geometría original capturada"
func _lab_geometry_text() -> String:return "1 ladrillo completo · una caja invisible\nMuestras XYZ obtenidas de triángulos fuente\nTextura PBR leída en coordenadas UV\nTres LODs independientes"
func _lab_source_text() -> String:return "El origen puede ser un escaneo autorizado o\nun modelo de prueba. Revisa el catálogo SHA-256.\nNO mostrar malla 3D original en ejecución.\nCalidad fotográfica: NO validada."
