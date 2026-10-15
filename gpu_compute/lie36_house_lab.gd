extends "res://lie28_building_lab.gd"
## Authored L-shaped two-storey scene: no procedural facade textures, no meshes.
const HouseEffect=preload("res://lie36_house_effect.gd")
var house_plan: Dictionary={}
func _ready() -> void:
    get_window().size=Vector2i(1280,800)
    state["camera_yaw"]=35.
    state["camera_elevation"]=19.
    state["distance_factor"]=1.85
    state["light_azimuth"]=-52.
    state["exposure"]=2.0
    state["variation"]=0.
    state["roof"]=true
    effect=HouseEffect.new(512)
    var plan: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://captures/liehouse36/house-plan.json"))
    if plan is Dictionary:house_plan=plan
    var world:=WorldEnvironment.new()
    var env:=Environment.new()
    env.background_mode=Environment.BG_COLOR
    env.background_color=Color(.045,.066,.094)
    world.environment=env
    var compositor:=Compositor.new()
    compositor.compositor_effects=[effect]
    world.compositor=compositor
    add_child(world)
    camera=Camera3D.new()
    camera.current=true
    camera.near=.001
    camera.far=65.
    add_child(camera)
    _ui()
    if effect.capture_loaded and not house_plan.is_empty():_apply()
    else:push_error("LIE36 real scan missing or invalid")
    _refresh()

func _ui() -> void:
    var ui:=CanvasLayer.new()
    add_child(ui)
    var heading:=_label(ui,"LIE · CASA ESCANEADA · 1.0 experimental",25)
    heading.position=Vector2(20,20)
    picture=TextureRect.new()
    picture.position=Vector2(294,68)
    picture.size=Vector2(695,695)
    picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
    picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    ui.add_child(picture)
    var left: VBoxContainer=_panel(ui,Vector2(18,76))
    _label(left,"CASA DE DOS PLANTAS EN L",16)
    _label(left,"Ladrillo LIE auténtico + mortero fotográfico\nFuente WALL04 con identidad SHA-256\nAberturas físicas en muestras\nCubierta y parapeto de mampostería\nSin mallas fuente rasterizadas.",12)
    _check(left,"roof","Mostrar cubierta escaneada")
    _label(left,"Prototipo visual: sin ventanas acristaladas,\ncarpintería, escaleras ni física estructural.",12)
    var right: VBoxContainer=_panel(ui,Vector2(995,76))
    _label(right,"CÁMARA Y LUZ",16)
    for pair in [["camera_yaw","Órbita"],["camera_elevation","Altura"],
                 ["distance_factor","Distancia"],["light_azimuth","Dirección de luz"],
                 ["light_power","Intensidad"],["exposure","Exposición"]]:
        _slider(right,pair[0],pair[1])
    _check(right,"shadows","Sombras")
    status=_label(right,"Preparando escaneo auténtico…",12)
    status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    status.custom_minimum_size.x=220

func _instances() -> Array:
    var result: Array=[]
    for item in house_plan.get("instances",[]):
        if not state["roof"] and item["group"] in ["roof","awning"]:continue
        var p: Array=item["position"]
        var pitch: float=float(item["pitch"])
        var yaw: float=float(item["yaw"])
        var basis: Basis=Basis(Vector3.RIGHT,pitch) if absf(pitch)>.0001 else Basis(Vector3.UP,yaw)
        result.append({"master":item["master"],"pose":Transform3D(basis,Vector3(p[0],p[1],p[2]))})
    return result

func agent_snapshot() -> Dictionary:
    var data: Dictionary=super.agent_snapshot()
    data["house"]={"layout":"L-shaped 2-storey","scan_source":"WALL04 CC BY 4.0 brick and CC0 photographic mortar",
      "plan_instances":house_plan.get("instances",[]).size(),"visual_only":true,"no_source_meshes":true}
    return data
