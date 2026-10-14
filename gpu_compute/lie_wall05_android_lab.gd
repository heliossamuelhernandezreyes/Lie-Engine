extends "res://lie_runtime_android_lab.gd"
const SharedWallEffect=preload("res://lie_wall05_shared_effect.gd")
const OpticalTransport=preload("res://lie_wall05_optical_transport.gd")
var _last_quality: int=-1
var _last_optical: int=-1
func _ready() -> void:
    state["quality_2x"]=false
    state["optical_codes"]=true
    state["scan_shadows"]=true
    super._ready()
func _coded_effect_factory() -> CompositorEffect:return SharedWallEffect.new(720)
func _transport_factory() -> CompositorEffect:return OpticalTransport.new()
func _instances() -> Array:
    var result: Array=[]
    for pose in effect.catalog["wall05"]["poses"]:
        var p: Array=pose["center"];var tone: float=pose["tone"]
        result.append({"master":"brick_wall","pose":Transform3D(Basis(Vector3.UP,float(pose["yaw_rad"])),Vector3(p[0],p[1],p[2])),"tint":[tone,tone,tone,0.]})
    result.append({"master":"joint_photo","pose":Transform3D.IDENTITY,"tint":[1.,1.,1.,0.]})
    return result
func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("values",{}) is Dictionary:
        var values: Dictionary=request.get("values",{})
        for key in ["quality_2x","optical_codes","scan_shadows"]:
            if values.has(key) and not values[key] is bool:return {"ok":false,"error":key+"_type","revision":revision}
    return super.command(request)
func _apply() -> void:
    if effect!=null:
        var quality: int=1 if state.get("quality_2x",false) else 0
        if quality!=_last_quality:effect.set_supersampling(quality==1);_last_quality=quality
    super._apply()
    if transport!=null:
        var optical: int=(1 if state.get("optical_codes",true) else 0)+(2 if state.get("scan_shadows",true) else 0)
        if optical!=_last_optical:
            transport.set_optical_options(bool(state.get("optical_codes",true)),bool(state.get("scan_shadows",true)))
            effect.invalidate_lighting();_last_optical=optical
func _ui() -> void:
    super._ui()
    for layer in get_children():
        if layer is CanvasLayer:
            for item in layer.get_children():
                if item is Label and item.text.begins_with("LIE ·"):item.text="LIE · Pared escaneada · 0.2.0"
    var box: Node=status.get_parent()
    _check(box,"quality_2x","Supermuestreo 2× (más coste)")
    _check(box,"optical_codes","Códigos ópticos direccionales")
    _check(box,"scan_shadows","Sombras según cara escaneada")
func _process(delta: float) -> void:
    var previous_report: int=_report_clock
    super._process(delta)
    if previous_report==_report_clock:return
    if status!=null and effect!=null and effect.gpu_ready:
        var c: Dictionary=effect.cache_metrics()
        status.text+="\nGeometría: %d · luz reutilizada: %d\nMaestro: 1 · instancias: 96\nInterior: %d × %d" % [c["geometry_rebuilds"],c["recovery_reuses"],c["internal_size"],c["internal_size"]]
