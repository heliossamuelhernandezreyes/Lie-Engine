extends "res://lie_wall01_coded_lab.gd"
## Real scan wall with four front-face micro patches per brick.
## 96 GPU shadow proxies are *only* for light visibility, not collision or render.
const MicroLightTransport=preload("res://lie_wall02_micro_transport.gd")
const MicroWallEffect=preload("res://lie_wall02_coded_effect.gd")

func _coded_source() -> String:
    return "res://captures/liewall02/light-model.json"

func _transport_factory() -> CompositorEffect:
    return MicroLightTransport.new()

func _coded_effect_factory() -> CompositorEffect:
    return MicroWallEffect.new(1080)

func _lab_heading() -> String:
    return "LIE-WALL-02 · 96 escaneos · 865 nodos RGB reales"

func _lab_geometry_text() -> String:
    return "96 ladrillos reales · 1 caja invisible\n4 nodos por cara frontal + 5 laterales\nGama lineal del escaneo original\n3 LOD visuales · 1 instancia de muro"

func _lab_source_text() -> String:
    return "Transporte LIE11 original: 2 rebotes\n96 proxies GPU exclusivamente para sombras\nNingún triángulo visible ni colisionador extra\nSin doble iluminación ni textura inventada"

func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot()
    result["micro_patches_per_brick"]=9
    result["front_micro_patches"]=4
    result["light_visibility_proxies"]=96
    result["wall_envelope_count"]=1 if has_node("InvisibleBrick/OnlyCollider") else 0
    result["shadow_metrics"]=transport.call("shadow_metrics") if transport!=null and transport.has_method("shadow_metrics") else {}
    return result
