extends "res://lie28_building_lab.gd"
## Authored L-shaped two-storey scene: no procedural facade textures, no meshes.
const HouseEffect=preload("res://lie36_house_effect.gd")
var house_plan: Dictionary={}
func _ready() -> void:
    get_window().size=Vector2i(1280,800)
    state["camera_yaw"]=-165.
    state["camera_elevation"]=24.
    state["distance_factor"]=1.85
    state["light_azimuth"]=-135.
    state["exposure"]=2.65
    state["variation"]=0.
    state["roof"]=true
    state["bounce"]=true
    state["seams"]=true
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
    _check(right,"bounce","Rebote dinámico entre muros")
    _check(right,"seams","Reparar microporos y uniones")
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
        var scale: Array=item.get("scale",[1,1,1])
        basis=basis.scaled_local(Vector3(scale[0],scale[1],scale[2]))
        result.append({"master":item["master"],"pose":Transform3D(basis,Vector3(p[0],p[1],p[2]))})
    return result

# Exact source-scan LOD per architectural INSTANCE (not 6K for every wall).
# Keep occluding backside surfaces at coarse density; closest visible faces
# receive substantially more records from the preassembled 96-brick panel.
func _apply() -> void:
    if camera==null or not effect.capture_loaded or house_plan.is_empty():return
    var target:=Vector3(0,2.65,0)
    var distance: float=8.6*float(state["distance_factor"])
    var yaw: float=deg_to_rad(float(state["camera_yaw"]))
    var elevation: float=deg_to_rad(float(state["camera_elevation"]))
    camera.fov=42.
    camera.position=target+Vector3(sin(yaw)*cos(elevation),sin(elevation),cos(yaw)*cos(elevation))*distance
    camera.look_at(target)
    var entries: Array=_instances()
    if entries.is_empty():return
    var limits: Array=effect.catalog["masters"]["brick"]["levels"]
    var cheapest: int=int(limits[2]["count"])
    var available: int=Effect.MAX_WORK-entries.size()*cheapest
    if entries.size()>Effect.MAX_INSTANCES or available<0:
        _metrics={"error":"work_budget","instances":entries.size()};return
    var score: Array=[]
    var forward: Vector3=-camera.basis.z
    for i in range(entries.size()):
        var pose: Transform3D=entries[i]["pose"]
        var direction: Vector3=pose.origin-camera.position
        var facing: float=direction.normalized().dot(forward)
        var priority: float=(maxf(facing,.02)+.08)/maxf(direction.length_squared(),.1)
        score.append({"index":i,"priority":priority})
    score.sort_custom(func(a,b):return a["priority"]>b["priority"])
    var levels: Array=[]
    levels.resize(entries.size())
    levels.fill(2)
    var medium_target: int=mini(75,entries.size())
    var medium_count: int=0
    for item in score:
        if medium_count>=medium_target:break
        var index: int=int(item["index"])
        var med: int=int(effect.catalog["masters"][entries[index]["master"]]["levels"][1]["count"])
        var delta: int=med-cheapest
        if delta>available:continue
        levels[index]=1
        available-=delta
        medium_count+=1
    var hero_count: int=0
    for item in score:
        if hero_count>=15:break
        var index: int=int(item["index"])
        if levels[index]!=1:continue
        var master: Dictionary=effect.catalog["masters"][entries[index]["master"]]
        var delta: int=int(master["levels"][0]["count"])-int(master["levels"][1]["count"])
        if delta>available:continue
        available-=delta
        levels[index]=0
        hero_count+=1
    var instances:=PackedFloat32Array()
    var jobs:=PackedInt32Array()
    var work: int=0
    var lod_counts: Array=[0,0,0]
    for i in range(entries.size()):
        var entry: Dictionary=entries[i]
        var pose: Transform3D=entry["pose"]
        var master: Dictionary=effect.catalog["masters"][entry["master"]]
        var lod: int=int(levels[i])
        var slice: Dictionary=master["levels"][lod]
        for vec in [pose.basis.x,pose.basis.y,pose.basis.z,pose.origin]:
            instances.append_array(PackedFloat32Array([vec.x,vec.y,vec.z,0]))
        var kind: int=["brick","window","door","slit"].find(entry["master"])
        instances.append_array(PackedFloat32Array([i*128.,float(maxi(kind,0)),0,0,1,1,1,1]))
        jobs.append_array(PackedInt32Array([slice["start"],slice["count"],i,work]))
        work+=int(slice["count"])
        lod_counts[lod]+=1
    var packet:=PackedFloat32Array()
    for vec in [camera.position,camera.basis.x,camera.basis.y,-camera.basis.z]:
        packet.append_array(PackedFloat32Array([vec.x,vec.y,vec.z,0]))
    packet.append_array(PackedFloat32Array([tan(deg_to_rad(camera.fov)*.5),1,.001,65]))
    var bytes: PackedByteArray=packet.to_byte_array()
    bytes.append_array(PackedInt32Array([work,entries.size(),effect.render_size,effect.render_size]).to_byte_array())
    var angle: float=deg_to_rad(float(state["light_azimuth"]))
    var radius: float=distance*.8
    var light: Vector3=target+Vector3(sin(angle)*radius,radius*.9,cos(angle)*radius)
    var light_pose:=Transform3D(Basis.IDENTITY,light).looking_at(target,Vector3.UP)
    var spacing: float=.003
    var v:=PackedFloat32Array([light.x,light.y,light.z,160*radius*radius*float(state["light_power"]),
        1,.93,.85,0,.40,.45,.55,float(state["exposure"]),
        1 if state["shadows"] else 0,1,spacing,spacing*.3])
    for vec in [light_pose.basis.x,light_pose.basis.y,-light_pose.basis.z]:
        v.append_array(PackedFloat32Array([vec.x,vec.y,vec.z,0]))
    v.append_array(PackedFloat32Array([1,1,1,0,1,1,1,0,1203,1,1 if state["bounce"] else 0,1 if state["seams"] else 0]))
    bytes.append_array(v.to_byte_array())
    var accepted: bool=effect.configure(bytes,instances.to_byte_array(),jobs.to_byte_array(),work)
    _metrics={"instances":entries.size(),"sample_invocations":work,
        "lod_distribution":lod_counts,"lod":0,
        "masters":effect.catalog["masters"].size(),"visible_source_meshes":0,
        "configured":accepted,"material":"LIE0.9 GGX/Smith/Fresnel",
        "raster":"LIE0.9 conservative bounds","illumination":"LIE37 dynamic per-panel GPU transport with blockers + one RGB bounce",
        "bounce":state["bounce"],"seams":state["seams"]}

func command(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("op")=="set_values":
        var values: Variant=request.get("values")
        if values is Dictionary and values.has("seams") and not values["seams"] is bool:
            return {"ok":false,"error":"boolean_seams","revision":revision}
        if values is Dictionary and values.has("bounce") and not values["bounce"] is bool:
            return {"ok":false,"error":"boolean_bounce","revision":revision}
    return super.command(request)

func agent_snapshot() -> Dictionary:
    var data: Dictionary=super.agent_snapshot()
    data["house"]={"layout":"L-shaped 2-storey","scan_source":"WALL04 CC BY 4.0 brick and CC0 photographic mortar",
      "plan_instances":house_plan.get("instances",[]).size(),"visual_only":true,"no_source_meshes":true}
    return data
