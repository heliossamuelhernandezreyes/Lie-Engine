extends "res://lie_brick01_lab.gd"
## One prebaked 96-brick sample master / one spatial envelope, lit by the
## ORIGINAL LIE11 GPU light transport (not a separate hand-painted gradient).
const CodedWallEffect=preload("res://lie_wall01_coded_effect.gd")
const LightTransport=preload("res://lie11_light_effect.gd")
const PRESETS=["neutral","warm_raking","cool_ambient"]
const SOURCE="res://captures/liewall01/light-model.json"
var transport: CompositorEffect
var light_model: Dictionary={}
var last_light_key: String=""
var last_absorption: int=-1
var last_shadows: bool=true
var last_direct_shadows: bool=true
var lighting_update_count: int=0

func _ready() -> void:
    state["master"]="real_scan_wall"
    state["mode"]="master"
    state["camera_yaw"]=12.0
    state["camera_elevation"]=9.0
    state["light_azimuth"]=-24.0
    state["light_power"]=1.0
    state["exposure"]=2.0
    state["variation"]=0.0 # Material tint was baked from scanned COLOR_0.
    state["lighting_preset"]="neutral"
    state["clay_absorption"]=0.0
    super._ready()

func _transport_factory() -> CompositorEffect:
    return LightTransport.new()

func _coded_source() -> String:
    return SOURCE

func _make_effect() -> CompositorEffect:
    transport=_transport_factory()
    var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(_coded_source()))
    if value is Dictionary:
        light_model=value
        if transport.has_method("assign_shadow_boxes"):
            if not transport.call("assign_shadow_boxes",light_model.get("direct_shadow_boxes",[])):
                push_error("LIE-WALL02: invalid real brick shadow visibility data")
        transport.call("configure",light_model)
    var coded:=_coded_effect_factory()
    coded.transport=transport
    return coded

func _coded_effect_factory() -> CompositorEffect:
    return CodedWallEffect.new(1080)

func _compositor_effects() -> Array[CompositorEffect]:
    var result: Array[CompositorEffect]=[]
    result.append(transport)
    result.append(effect)
    return result

func _camera_distance_multiplier() -> float:return 1.48
func _lab_heading() -> String:return "LIE-WALL-01 · Escaneo auténtico + inyección LIE11"
func _lab_geometry_text() -> String:
    return "96 ladrillos escaneados · 1 caja invisible\n1 rango de muro por LOD, 3 niveles\nColor COLOR_0 lineal original\nMortero procedural claramente identificado"
func _lab_source_text() -> String:
    return "Luz calculada en LIE11 (nodos XYZ)\nAbsorción / RGB en códigos independientes\nLIE33 recibe irradiancia directamente\nSin doble luz ambiente ni mallas visibles"

func _extra_light_controls(parent: VBoxContainer) -> void:
    _label(parent,"INYECCIÓN RGB POR NODOS · LIE11",12)
    _button(parent,"Neutra · frontal",func():command({"op":"set_values","values":{
        "lighting_preset":"neutral","light_azimuth":0.0,"light_power":1.0}}))
    _button(parent,"Cálida · rasante lateral",func():command({"op":"set_values","values":{
        "lighting_preset":"warm_raking","light_azimuth":-72.0,"light_power":1.2}}))
    _button(parent,"Fría · iluminación lateral",func():command({"op":"set_values","values":{
        "lighting_preset":"cool_ambient","light_azimuth":63.0,"light_power":1.0}}))
    _label(parent,"Absorción codificada de arcilla",12)
    var slider:=HSlider.new()
    slider.min_value=0.0;slider.max_value=.65;slider.step=.05
    slider.custom_minimum_size=Vector2(215,24)
    slider.value_changed.connect(func(v: float):command({"op":"set_values","values":{"clay_absorption":v}}))
    parent.add_child(slider)
    controls["clay_absorption"]=slider

func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("values",{}) is Dictionary:
        var values: Dictionary=request.get("values",{})
        if values.has("lighting_preset") and values["lighting_preset"] not in PRESETS:
            return {"ok":false,"error":"lighting_preset","revision":revision}
        if values.has("clay_absorption"):
            if not (values["clay_absorption"] is float or values["clay_absorption"] is int):
                return {"ok":false,"error":"absorption_type","revision":revision}
            if not is_finite(float(values["clay_absorption"])) or float(values["clay_absorption"])<0.0 or float(values["clay_absorption"])>.65:
                return {"ok":false,"error":"absorption_range","revision":revision}
    return super.command(request)

func _direct_shadow_enabled() -> bool:
    return bool(state["shadows"])

func _apply() -> void:
    if not light_model.is_empty() and effect!=null and effect.get("capture_loaded"):
        var presets: Dictionary={
            "neutral":Vector3(1.0,.93,.86),
            "warm_raking":Vector3(1.0,.57,.31),
            "cool_ambient":Vector3(.44,.72,1.0)
        }
        var selected: Vector3=presets[state["lighting_preset"]]
        var angle: float=deg_to_rad(float(state["light_azimuth"]))
        var size: Array=effect.get("catalog")["masters"]["real_scan_wall"]["bounds_size"]
        var center_arr: Array=effect.get("catalog")["masters"]["real_scan_wall"].get("bounds_center",[0,0,0])
        var center:=Vector3(float(center_arr[0]),float(center_arr[1]),float(center_arr[2]))
        var reach: float=maxf(1.0,float(size[0])*.48)
        var light_position:=center+Vector3(sin(angle)*reach,.78,cos(angle)*reach+.25)
        var power: float=55.0*float(state["light_power"])
        var key: String=JSON.stringify([state["lighting_preset"],float(state["light_azimuth"]),power])
        var absorption: int=int(round(float(state["clay_absorption"])*1000.0))
        var shadows: bool=bool(state["shadows"])
        var direct_enabled: bool=_direct_shadow_enabled()
        var direct_changed: bool=direct_enabled!=last_direct_shadows
        if key!=last_light_key or absorption!=last_absorption or shadows!=last_shadows or direct_changed or not transport.get("gpu_ready"):
            light_model["lights"][0]["position"]=[light_position.x,light_position.y,light_position.z]
            light_model["lights"][0]["power_rgb"]=[power*selected.x,power*selected.y,power*selected.z]
            light_model["lights"][0]["radius"]=6.0
            light_model["materials"]["clay"]["absorption_code"]=absorption
            var original_core: Array=light_model.get("wall_opaque_core",[])
            if original_core.is_empty():
                original_core=light_model.get("blockers",[]).duplicate(true)
                light_model["wall_opaque_core"]=original_core
            light_model["blockers"]=original_core.duplicate(true) if shadows else []
            if transport.has_method("set_direct_shadow_enabled"):
                transport.call("set_direct_shadow_enabled",direct_enabled)
            if not transport.get("gpu_ready") or shadows!=last_shadows:
                transport.call("configure",light_model)
            else:
                if key!=last_light_key:transport.call("set_light_codes",light_model)
                if absorption!=last_absorption:transport.call("set_material_codes",light_model)
                # Re-run ORIGINAL light injection with unchanged RGB values
                # when only the optional direct shadow GPU buffer changes.
                if direct_changed and key==last_light_key:
                    transport.call("set_light_codes",light_model)
            last_light_key=key
            last_absorption=absorption
            last_shadows=shadows
            last_direct_shadows=direct_enabled
            lighting_update_count+=1
            effect.call("invalidate_lighting")
    super._apply()

func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot()
    result["source"]="genuine CC BY scanned Stratford brick COLOR_0"
    result["wall_brick_count"]=96
    result["wall_envelope_count"]=1 if has_node("InvisibleBrick/OnlyCollider") else 0
    result["wall_renderer_instances"]=_metrics.get("instances",0)
    result["lighting_node_count"]=light_model.get("patches",[]).size()
    result["lighting_preset"]=state.get("lighting_preset")
    result["lighting_updates"]=lighting_update_count
    result["transport_gpu_ready"]=transport!=null and transport.get("gpu_ready")
    result["transport_frame_count"]=transport.get("frame_count") if transport!=null else 0
    result["transport_metrics"]=transport.call("transport_metrics") if transport!=null else {}
    result["coded_light"]=effect.call("node_light_status") if effect!=null else {}
    return result

func _exit_tree() -> void:
    super._exit_tree()
    if transport!=null:transport.call("shutdown")
