extends "res://lie_wall10_android_lab.gd"
const PersistentEffect=preload("res://lie_wall11_persistent_effect.gd")
func _ready() -> void:
    state["persistent_visibility"]=true;state["block_access"]=true;state["visibility_diagnostics"]=false
    super._ready()
func _coded_effect_factory() -> CompositorEffect:return PersistentEffect.new(720)
func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("op")=="sample_address":
        for key in request:
            if key not in ["op","asset_id","lod","sample_index"]:return {"ok":false,"error":"sample_address_field","revision":revision}
        if not request.get("asset_id") is String:return {"ok":false,"error":"asset_id_type","revision":revision}
        for key in ["lod","sample_index"]:
            var value: Variant=request.get(key)
            if not (value is int or value is float) or not is_finite(float(value)) or floorf(float(value))!=float(value) or value<0 or value>16777215:return {"ok":false,"error":key+"_type","revision":revision}
        var address: Dictionary=effect.sample_identity.address(request["asset_id"],int(request["lod"]),int(request["sample_index"]))
        if address.is_empty():return {"ok":false,"error":"sample_address_range","revision":revision}
        address.erase("instance_id")
        return {"ok":true,"revision":revision,"address":address,"resident":effect.gpu_ready,"bank_generation":effect._sample_handle.get("generation",0),"scope":"master-source address; runtime handle generation is separately validated"}
    if request is Dictionary and request.get("values",{}) is Dictionary:
        for key in ["persistent_visibility","block_access","visibility_diagnostics"]:
            if request["values"].has(key) and not request["values"][key] is bool:return {"ok":false,"error":key+"_type","revision":revision}
    return super.command(request)
func _apply() -> void:
    if effect!=null:effect.set_identity_options(bool(state["persistent_visibility"]),bool(state["block_access"]),bool(state["visibility_diagnostics"]))
    super._apply()
func _ui() -> void:
    super._ui();var box: Node=status.get_parent()
    _label(box,"IDENTIDAD Y CACHÉ",19)
    _check(box,"persistent_visibility","Conservar sombras por muestra")
    _check(box,"block_access","Acceso directo por bloques")
    _check(box,"visibility_diagnostics","Contar consultas GPU (más coste)")
    _label(box,"La cámara reutiliza las sombras conocidas.\nMover una luz actualiza su caché.",15)
    for layer in get_children():
        if layer is CanvasLayer:
            for item in layer.get_children():
                if item is Label and item.text.begins_with("LIE ·"):item.text="LIE · Identidad y luz persistente · 0.8.0"
func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot()
    for key in ["persistent_visibility","block_access","visibility_diagnostics"]:
        if not result["control_contract"]["booleans"].has(key):result["control_contract"]["booleans"].append(key)
    result["control_contract"]["sample_address"]={"fields":["asset_id","lod","sample_index"],"read_only":true,"source_bank_sha256":effect.catalog.get("sha256","")}
    return result
