extends "res://lie_wall03_coverage_lab.gd"
## WALL04 keeps WALL03's single invisible BoxShape3D and 96 original bricks.
## This experimental captured mortars lab is NOT an accepted photoreal master.
const CapturedMortarEffect=preload("res://lie_wall04_mortar_effect.gd")
const FixedSelfShadowTransport=preload("res://lie_wall04_transport.gd")

func _coded_source() -> String:
    return "res://captures/liewall04/light-model.json"

func _transport_factory() -> CompositorEffect:
    return FixedSelfShadowTransport.new()

func _coded_effect_factory() -> CompositorEffect:
    return CapturedMortarEffect.new(1080)

func _lab_heading() -> String:
    return "LIE-WALL-04 · Mortero fotográfico experimental"

func _lab_geometry_text() -> String:
    return "96 ladrillos fuente byte-inmutables · 1 caja invisible\n"+\
           "Huella visual XY del ladrillo extendida hasta junta de 6 mm\n"+\
           "Mortero XYZ CC0 8K · nivel frontal escaneado · 3 LOD"

func _lab_source_text() -> String:
    return "MORTAR-01: Poly Haven CC0, recortes H/V\n"+\
           "NO aprobado: máscaras todavía sin revisión G1\n"+\
           "Relieve relativo, escala de altura no certificada\n"+\
           "LIE11: mismos 872 nodos RGB y 96 proxies sólo de luz"

func agent_snapshot() -> Dictionary:
    var snapshot: Dictionary=super.agent_snapshot()
    var snapshot_catalog: Dictionary=effect.get("catalog") if effect!=null else {}
    var proof: Dictionary=snapshot_catalog.get("wall04",{})
    snapshot["mortared_by_photographic_3d_samples"]=true
    snapshot["source_mortar_G1_reviewed"]=bool(proof.get("mortar_source_masks_reviewed",false))
    snapshot["source_mortar_metric_height"]=bool(proof.get("mortar_source_height_absolute_mm_verified",false))
    snapshot["original_brick_records_verified"]=bool(proof.get("original_brick_samples_byte_identical",false))
    snapshot["original_wall03_sha"]=str(proof.get("wall03_original_sha256",""))
    snapshot["mortar_source_sha"]=str(proof.get("mortar01_sha256",""))
    snapshot["legacy_planar_mortar_enabled"]=false
    snapshot["hero_quality_accepted"]=false
    snapshot["renderer"]="LIE11 coded RGB light -> genuine scan brick samples + photographed XYZ mortar, no planar mortar"
    return snapshot
