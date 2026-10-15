extends "res://lie_wall07_android_lab.gd"
const FieldTransport=preload("res://lie_wall08_field_transport.gd")
const LightRegistry=preload("res://lie_light_registry.gd")
const LightWorld=preload("res://lie_light_world.gd")
const PointEmitter=preload("res://lie_point_emitter_3d.gd")
var light_registry=LightRegistry.new()
var light_world: Node3D
var key_emitter: Node3D
var fill_emitter: Node3D
var _last_separate: bool=true

func _ready() -> void:
    state["fill_enabled"]=true;state["fill_power"]=.32;state["fill_azimuth"]=55.;state["separate_lights"]=true
    super._ready()

func _transport_factory() -> CompositorEffect:return FieldTransport.new()

func _make_effect() -> CompositorEffect:
    var coded: CompositorEffect=super._make_effect()
    if not light_model.is_empty():
        light_world=LightWorld.new();light_world.name="LieLights";add_child(light_world)
        light_registry=light_world.registry
        key_emitter=PointEmitter.new();key_emitter.name="WarmKey";key_emitter.light_id="key";light_world.add_child(key_emitter)
        fill_emitter=PointEmitter.new();fill_emitter.name="CoolFill";fill_emitter.light_id="fill";light_world.add_child(fill_emitter)
        var key: Dictionary=light_model["lights"][0];var p: Array=key["position"];var rgb: Array=key["power_rgb"]
        key_emitter.position=Vector3(p[0],p[1],p[2]);key_emitter.power_rgb_linear=Vector3(rgb[0],rgb[1],rgb[2])
        fill_emitter.power_rgb_linear=Vector3.ZERO
        light_world.refresh();light_world.codes_changed.connect(_accept_light_snapshot)
        light_model["lights"]=light_registry.snapshot()["lights"]
        transport.configure(light_model)
    return coded

func _accept_light_snapshot(snapshot: Dictionary) -> void:
    if transport==null or light_model.is_empty():return
    light_model["lights"]=snapshot["lights"]
    if not transport.gpu_ready or transport.optical_metrics()["lights"]!=snapshot["lights"].size():transport.configure(light_model)
    else:transport.set_light_codes(light_model)
    if effect!=null:effect.invalidate_lighting()

func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("values",{}) is Dictionary:
        var values: Dictionary=request.get("values",{})
        for key in ["fill_enabled","separate_lights"]:
            if values.has(key) and not values[key] is bool:return {"ok":false,"error":key+"_type","revision":revision}
        for key in ["fill_power","fill_azimuth"]:
            if not values.has(key):continue
            if not (values[key] is int or values[key] is float):return {"ok":false,"error":key+"_type","revision":revision}
            var value: float=float(values[key]);var low: float=0. if key=="fill_power" else -85.;var high: float=2. if key=="fill_power" else 85.
            if not is_finite(value) or value<low or value>high:return {"ok":false,"error":key+"_range","revision":revision}
    return super.command(request)

func _apply() -> void:
    if light_model.get("lights",[]).size()==2 and effect!=null:
        var bounds: Dictionary=effect.catalog["masters"]["real_scan_wall"]
        var c: Array=bounds["bounds_center"];var size: Array=bounds["bounds_size"]
        var angle: float=deg_to_rad(float(state["fill_azimuth"]));var reach: float=maxf(1.,float(size[0])*.48)
        var p:=Vector3(c[0],c[1],c[2])+Vector3(sin(angle)*reach,.34,cos(angle)*reach+.25)
        var power: float=55.*float(state["fill_power"]) if state["fill_enabled"] else 0.
        fill_emitter.position=p;fill_emitter.power_rgb_linear=Vector3(power*.44,power*.72,power)
    super._apply()
    if transport==null or light_model.is_empty():return
    var key: Dictionary=light_model["lights"][0];var p: Array=key["position"];var rgb: Array=key["power_rgb"]
    key_emitter.position=Vector3(p[0],p[1],p[2]);key_emitter.power_rgb_linear=Vector3(rgb[0],rgb[1],rgb[2]);light_world.refresh()
    var separate: bool=state["separate_lights"]
    if separate!=_last_separate:
        transport.set_separate_lights(separate);effect.invalidate_lighting();_last_separate=separate

func _field_slider(box: Node,key: String,title: String,low: float,high: float) -> void:
    _label(box,title,17)
    var slider:=HSlider.new();slider.min_value=low;slider.max_value=high;slider.step=.01
    slider.value=state[key];slider.custom_minimum_size=Vector2(270,34)
    slider.value_changed.connect(func(v: float):command({"op":"set_values","values":{key:v}}))
    box.add_child(slider);controls[key]=slider

func _ui() -> void:
    super._ui()
    var box: Node=status.get_parent()
    _label(box,"SEGUNDA LUZ · FRÍA",19)
    _check(box,"fill_enabled","Encender segunda luz")
    _field_slider(box,"fill_power","Intensidad de segunda luz",0.,2.)
    _field_slider(box,"fill_azimuth","Dirección de segunda luz",-85.,85.)
    _check(box,"separate_lights","Conservar dirección de cada luz")
    for layer in get_children():
        if layer is CanvasLayer:
            for item in layer.get_children():
                if item is Label and item.text.begins_with("LIE ·"):item.text="LIE · Luz por superficie · 0.5.0"

func agent_snapshot() -> Dictionary:
    var result: Dictionary=super.agent_snapshot()
    result["control_contract"]=result["control_contract"].duplicate(true)
    for key in ["fill_enabled","separate_lights"]:
        if not result["control_contract"]["booleans"].has(key):result["control_contract"]["booleans"].append(key)
    result["control_contract"]["limits"]["fill_power"]=[0.,2.]
    result["control_contract"]["limits"]["fill_azimuth"]=[-85.,85.]
    result["light_registry"]=light_registry.snapshot()
    return result
