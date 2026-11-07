extends Node3D
const Effect=preload("res://lie_construction_scene_effect.gd")
var effect: CompositorEffect
var camera: Camera3D
var world_environment: WorldEnvironment
var picture: TextureRect
var texture: Texture2DRD
var selector: OptionButton
var controls: Dictionary={}
var state: Dictionary={"mode":"corner","seed":2102,"yaw":32.,"elevation":22.,"light":-35.,"zoom":1.,"focus_x":0.,"focus_y":0.,"normals":true,"shadows":true,"occluder":true,"reverse_banks":false,"door_angle":0.,"lod":-1}
var revision: int=0
var metrics: Dictionary={}
var recipe: Dictionary={}
func _ready() -> void:
    effect=Effect.new(960)
    if not effect.capture_loaded:metrics={"error":effect.failure};return
    camera=Camera3D.new();add_child(camera);camera.current=true
    world_environment=WorldEnvironment.new();add_child(world_environment);world_environment.environment=Environment.new();world_environment.compositor=Compositor.new();world_environment.compositor.compositor_effects=[effect]
    var layer:=CanvasLayer.new();add_child(layer);var bg:=ColorRect.new();bg.color=Color(.03,.037,.047);bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layer.add_child(bg)
    picture=TextureRect.new();picture.position=Vector2(10,10);picture.size=Vector2(800,800);layer.add_child(picture)
    var title:=Label.new();title.position=Vector2(830,15);title.text="LIE · CONSTRUCCIÓN FOTOGRÁFICA\n\nEsquina intercalada y abertura real\nMortero de juntas fotografiadas\nPerfiles con superficies PBR 8K\n\nNormales ópticas independientes\nProfundidad y sombras compartidas\n\nPowered by Poly Haven\nLadrillo: Centre-of-Archaeology\n\nFormas de perfiles: autoría LIE\nSin malla fuente en el render";layer.add_child(title)
    selector=OptionButton.new();selector.position=Vector2(830,330);selector.size=Vector2(300,34)
    for mode in effect.manifest.modes:selector.add_item(mode.replace("asset_","").replace("_"," "))
    selector.item_selected.connect(func(i: int):command({"op":"set_values","values":{"mode":effect.manifest.modes[i]}}));layer.add_child(selector)
    var y: int=380
    for key in ["yaw","elevation","light","zoom","door_angle"]:
        var label:=Label.new();label.text={"yaw":"Giro de cámara","elevation":"Elevación","light":"Giro de luz","zoom":"Distancia","door_angle":"Ángulo de puerta"}[key];label.position=Vector2(830,y);layer.add_child(label)
        var slider:=HSlider.new();slider.position=Vector2(830,y+22);slider.size=Vector2(280,22);slider.min_value=.25 if key=="zoom" else 0. if key=="door_angle" else -180.;slider.max_value=2. if key=="zoom" else 110. if key=="door_angle" else 180.;slider.step=.01 if key=="zoom" else 1.;slider.value=state[key]
        slider.value_changed.connect(func(value: float):command({"op":"set_values","values":{key:value}}));controls[key]=slider;layer.add_child(slider);y+=57
    for key in ["normals","shadows"]:
        var checkbox:=CheckBox.new();checkbox.position=Vector2(830,y);checkbox.text="Detalle normal" if key=="normals" else "Sombras comunes";checkbox.button_pressed=true;checkbox.toggled.connect(func(value: bool):command({"op":"set_values","values":{key:value}}));layer.add_child(checkbox);controls[key]=checkbox;y+=30
    var button:=Button.new();button.position=Vector2(830,y);button.text="Semilla 2102 / 7319";button.pressed.connect(func():command({"op":"set_values","values":{"seed":7319 if state.seed==2102 else 2102}}));layer.add_child(button)
    update_scene()
func command(request: Dictionary) -> Dictionary:
    if request.get("op")=="snapshot":return {"ok":true,"revision":revision,"state":state.duplicate(),"metrics":metrics.duplicate()}
    if request.get("op")!="set_values" or not request.get("values") is Dictionary:return {"ok":false,"error":"command"}
    if request.has("expected_revision") and (not request.expected_revision is int or request.expected_revision!=revision):return {"ok":false,"error":"revision"}
    var candidate: Dictionary=state.duplicate()
    for key in request.values:
        var value: Variant=request.values[key]
        if key=="mode":
            if not value is String or value not in effect.manifest.modes:return {"ok":false,"error":"mode"}
        elif key=="seed":
            if not value is int or value not in [2102,7319]:return {"ok":false,"error":"seed"}
        elif key in ["normals","shadows","occluder","reverse_banks"]:
            if not value is bool:return {"ok":false,"error":"boolean"}
        elif key=="lod":
            if not value is int or value< -1 or value>4:return {"ok":false,"error":"lod"}
        elif key in ["yaw","elevation","light","zoom","focus_x","focus_y","door_angle"]:
            if not (value is int or value is float) or not is_finite(float(value)):return {"ok":false,"error":"number"}
            if key=="zoom" and (value<.25 or value>2.):return {"ok":false,"error":"zoom"}
            if key in ["yaw","elevation","light"] and abs(value)>180:return {"ok":false,"error":"angle"}
            if key in ["focus_x","focus_y"] and abs(value)>3:return {"ok":false,"error":"focus"}
            if key=="door_angle" and (value<0 or value>110):return {"ok":false,"error":"door"}
        else:return {"ok":false,"error":"key"}
        candidate[key]=value
    if not FileAccess.file_exists(effect.scene_root()+candidate.mode+"-"+str(candidate.seed)+".json"):return {"ok":false,"error":"scene"}
    state=candidate;revision+=1;update_scene();return {"ok":true,"revision":revision}
func update_scene() -> void:
    recipe=JSON.parse_string(FileAccess.get_file_as_string(effect.scene_root()+state.mode+"-"+str(state.seed)+".json"))
    if recipe.scene_identity!=effect.manifest.scene_identity or recipe.bank_bindings!=effect.manifest.bank_bindings:metrics={"error":"scene_bank_identity"};return
    selector.select(effect.manifest.modes.find(state.mode))
    for key in controls:
        if controls[key] is HSlider:controls[key].set_value_no_signal(state[key])
        else:controls[key].set_pressed_no_signal(state[key])
    var a: Array=recipe.target;var target:=Vector3(a[0]+state.focus_x,a[1]+state.focus_y,a[2]);var dim: Array=recipe.bounds_m;var extent: float=maxf(dim[0],maxf(dim[1],dim[2]));var distance: float=extent*1.75*state.zoom
    var yaw: float=deg_to_rad(state.yaw);var elevation: float=deg_to_rad(state.elevation);camera.fov=42
    camera.position=target+Vector3(sin(yaw)*cos(elevation),sin(elevation),cos(yaw)*cos(elevation))*distance
    # Keep a valid camera basis even for exact overhead commands.
    camera.look_at(target,Vector3.FORWARD if absf(cos(elevation))<.0001 else Vector3.UP)
    var entries: Array=[];var levels: Array=[];var work: int=0
    for e in recipe.instances:
        if String(e.id).ends_with("/occluder") and not state.occluder:continue
        var bank: int=effect.manifest.banks.find(e.bank)
        if bank<0:metrics={"error":"bank"};return
        var ranges: Array=effect.banks[bank].catalog.masters[e.master].levels;var level: int=mini(state.lod if state.lod>=0 else e.lod,ranges.size()-1)
        entries.append(e);levels.append(level);work+=int(ranges[level].count)
    while work>effect.work_capacity():
        var changed: bool=false
        for i in range(entries.size()):
            var bank: int=effect.manifest.banks.find(entries[i].bank);var ranges: Array=effect.banks[bank].catalog.masters[entries[i].master].levels
            if levels[i]+1<ranges.size():work-=int(ranges[levels[i]].count)-int(ranges[levels[i]+1].count);levels[i]+=1;changed=true
            if work<=effect.work_capacity():break
        if not changed:metrics={"error":"work_budget"};return
    var instances:=PackedFloat32Array();var jobs:=PackedInt32Array();work=0
    for i in range(entries.size()):
        var e: Dictionary=entries[i];var bank: int=effect.manifest.banks.find(e.bank);var c: Array=e.basis_columns;var basis:=Basis(Vector3(c[0][0],c[0][1],c[0][2]),Vector3(c[1][0],c[1][1],c[1][2]),Vector3(c[2][0],c[2][1],c[2][2]));var s: Array=e.scale;basis=basis.scaled_local(Vector3(s[0],s[1],s[2]));var p: Array=e.origin;var origin:=Vector3(p[0],p[1],p[2])
        if state.mode=="door" and String(e.id).ends_with("/leaf"):
            var rotation:=Basis(Vector3.UP,deg_to_rad(state.door_angle));origin+=Vector3(-.41,0,0)+rotation*Vector3(.41,0,0);basis=rotation*basis
        for v in [basis.x,basis.y,basis.z,origin]:instances.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
        var tint: Array=e.tint;var clip: Dictionary=effect.banks[bank].catalog.masters[e.master].get("cut_clip",{})
        instances.append_array(PackedFloat32Array([i*8,bank,clip.get("sense",0),clip.get("plane_m",0),tint[0],tint[1],tint[2],e.roughness_delta]))
        var range_data: Dictionary=effect.banks[bank].catalog.masters[e.master].levels[levels[i]];jobs.append_array(PackedInt32Array([range_data.start,range_data.count,i,work]));work+=int(range_data.count)
    var packet:=PackedFloat32Array()
    for v in [camera.position,camera.basis.x,camera.basis.y,-camera.basis.z]:packet.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    packet.append_array(PackedFloat32Array([tan(deg_to_rad(camera.fov)*.5),1,.0005,100]));var bytes: PackedByteArray=packet.to_byte_array();bytes.append_array(PackedInt32Array([work,entries.size(),effect.render_size,effect.render_size]).to_byte_array())
    var angle: float=deg_to_rad(state.light);var r: float=distance*.8;var light: Vector3=target+Vector3(sin(angle)*r,.9*r,cos(angle)*r);var pose:=Transform3D(Basis.IDENTITY,light).looking_at(target,Vector3.UP)
    var values:=PackedFloat32Array([light.x,light.y,light.z,55*r*r,1,.96,.91,0,.32,.35,.40,1.6,1 if state.shadows else 0,1,.0007,.00022])
    for v in [pose.basis.x,pose.basis.y,-pose.basis.z]:values.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    values.append_array(PackedFloat32Array([1,1,1 if state.reverse_banks else 0,0,1,1,1,0,2102,1,0,1 if state.normals else 0]));bytes.append_array(values.to_byte_array())
    metrics={"configured":effect.configure(bytes,instances.to_byte_array(),jobs.to_byte_array(),work),"instances":entries.size(),"work":work,"source_mesh_draws":0,"banks":effect.banks.size()}
func _process(_delta: float) -> void:
    if effect.gpu_ready and texture==null:texture=Texture2DRD.new();texture.texture_rd_rid=effect.output_rid;picture.texture=texture
func _exit_tree() -> void:
    if texture!=null:texture.texture_rd_rid=RID()
    if effect!=null:effect.shutdown()
