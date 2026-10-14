extends "res://lie_wall04_mortar_lab.gd"
## Mobile controls use the same validated WALL04 commands and source bank.
var _radius_state: int=-1
var _report_clock: int=0
var _report_frames: int=0

func _ready() -> void:
    state["energy_radius"]=false
    super._ready()
    RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
    _report_clock=Time.get_ticks_usec()

func _coded_effect_factory() -> CompositorEffect:
    return CapturedMortarEffect.new(720)

func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("values",{}) is Dictionary:
        var values: Dictionary=request.get("values",{})
        if values.has("energy_radius") and not values["energy_radius"] is bool:
            return {"ok":false,"error":"energy_radius_type","revision":revision}
    return super.command(request)

func _apply() -> void:
    var selected: int=1 if state.get("energy_radius",false) else 0
    var changed: bool=selected!=_radius_state and not light_model.is_empty()
    if changed:
        if selected==1:
            light_model["secondary_radii"]={"mode":"irradiance","radius_max":6.0,"radius_decay":.82,"irradiance_cutoff":.001}
        else:light_model.erase("secondary_radii")
        _radius_state=selected
    super._apply()
    if changed and transport!=null:
        transport.call("configure",light_model)
        effect.call("invalidate_lighting")

func _slider(parent: Node,key: String,title: String) -> void:
    _label(parent,title,17)
    var item:=HSlider.new();item.min_value=LIMITS[key][0];item.max_value=LIMITS[key][1]
    item.step=.01;item.custom_minimum_size=Vector2(270,34)
    item.value_changed.connect(func(v: float):command({"op":"set_values","values":{key:v}}))
    parent.add_child(item);controls[key]=item

func _ui() -> void:
    var ui:=CanvasLayer.new();add_child(ui)
    var title:=_label(ui,"LIE · Pared escaneada · 0.1.0",25);title.position=Vector2(24,16)
    picture=TextureRect.new();picture.position=Vector2(18,62);picture.size=Vector2(900,720)
    picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    ui.add_child(picture)
    var panel:=PanelContainer.new();panel.position=Vector2(944,62);panel.size=Vector2(318,720)
    var style:=StyleBoxFlat.new();style.bg_color=Color(.04,.055,.075,.98)
    for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:style.set_content_margin(side,12)
    panel.add_theme_stylebox_override("panel",style);ui.add_child(panel)
    var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
    panel.add_child(scroll)
    var box:=VBoxContainer.new();box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    box.add_theme_constant_override("separation",8);scroll.add_child(box)
    _label(box,"CÁMARA Y LUZ",19)
    for pair in [["camera_yaw","Órbita"],["camera_elevation","Altura"],["distance_factor","Distancia"],
            ["light_azimuth","Dirección de luz"],["light_power","Intensidad"],["exposure","Exposición"]]:
        _slider(box,pair[0],pair[1])
    _check(box,"shadows","Sombras")
    _check(box,"direct_shadow_proxies","Sombra de ladrillos")
    _check(box,"energy_radius","Radio energético")
    for pair in [["neutral","Luz neutra",-22.,1.],["warm_raking","Luz cálida rasante",-72.,1.2],["cool_ambient","Luz fría",63.,1.]]:
        var preset: String=pair[0];var angle: float=pair[2];var power: float=pair[3]
        var button:=Button.new();button.text=pair[1];button.custom_minimum_size.y=42
        button.pressed.connect(func():command({"op":"set_values","values":{"lighting_preset":preset,"light_azimuth":angle,"light_power":power}}))
        box.add_child(button)
    _label(box,"Absorción de arcilla",17)
    var absorption:=HSlider.new();absorption.min_value=0;absorption.max_value=.65;absorption.step=.05
    absorption.custom_minimum_size=Vector2(270,34)
    absorption.value_changed.connect(func(v: float):command({"op":"set_values","values":{"clay_absorption":v}}))
    box.add_child(absorption);controls["clay_absorption"]=absorption
    status=_label(box,"Preparando pared…",16);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    status.custom_minimum_size.x=270
    var note:=_label(box,"96 ladrillos · una envolvente\nMortero experimental\nDesliza este panel para ver más",14)
    note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.custom_minimum_size.x=270

func _process(delta: float) -> void:
    super._process(delta)
    var now: int=Time.get_ticks_usec()
    if now-_report_clock<500000 or status==null:return
    if effect!=null and effect.get("gpu_ready"):
        var frames: int=int(effect.get("frame_count"))
        var rate: float=float(frames-_report_frames)*1.0e6/float(now-_report_clock)
        var lighting: Dictionary=transport.call("transport_metrics")
        status.text="Pantalla: %d FPS\nReconstrucción: %.1f/s\nLuz: %d cálculos\nBanco: %d carga\nBúferes LIE: %.1f MiB" % [Engine.get_frames_per_second(),rate,lighting["solves"],effect.get("asset_uploads"),float(effect.get("allocation_bytes"))/1048576.0]
        _report_frames=frames
    _report_clock=now
