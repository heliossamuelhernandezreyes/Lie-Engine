extends Node3D
const Effect=preload("res://lie_construction_scene_effect.gd")
const Field=preload("res://lie_field_quality_transport.gd")
const Adapter=preload("res://lie_construction_field_adapter.gd")
const World=preload("res://lie_light_world.gd")
const Emitter=preload("res://lie_point_emitter_3d.gd")
var transport: CompositorEffect
var light_model: Dictionary={}
var light_world: Node3D
var key_emitter: Node3D
var fill_emitter: Node3D
var _field_geometry: String=""
var _materials: Dictionary={}
var _building: bool=false
var _last_light_snapshot: Dictionary={}

var effect: CompositorEffect
var camera: Camera3D
var world_environment: WorldEnvironment
var picture: TextureRect
var texture: Texture2DRD
var selector: OptionButton
var controls: Dictionary={}
var state: Dictionary={"mode":"corner","seed":2102,"yaw":32.,"elevation":22.,"light":-35.,"zoom":1.,"focus_x":0.,"focus_y":0.,"normals":true,"shadows":true,"occluder":true,"reverse_banks":false,"door_angle":0.,"lod":-1,"field_lighting":true,"indirect":true,"key_enabled":true,"fill_enabled":true,"fill_power":.32,"bounces":2,"energy_radius":false,"ambient":1.}
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
    var scroll:=ScrollContainer.new();scroll.position=Vector2(825,10);scroll.size=Vector2(320,800);layer.add_child(scroll);var box:=VBoxContainer.new();box.custom_minimum_size=Vector2(295,0);box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(box)
    var title:=Label.new();title.text="LIE · CONSTRUCCIÓN\nMateriales fotográficos 8K\nPerfiles de autoría del proyecto";box.add_child(title)
    selector=OptionButton.new()
    for mode in effect.manifest.modes:selector.add_item(mode.replace("asset_","").replace("_"," "))
    selector.item_selected.connect(func(i: int):command({"op":"set_values","values":{"mode":effect.manifest.modes[i]}}));box.add_child(selector)
    for key in ["yaw","elevation","light","zoom","door_angle","fill_power","bounces","ambient"]:
        var label:=Label.new();label.text={"yaw":"Giro de cámara","elevation":"Elevación","light":"Giro de luz","zoom":"Distancia","door_angle":"Ángulo de puerta","fill_power":"Intensidad de segunda luz","bounces":"Rebotes","ambient":"Luz ambiente"}[key];box.add_child(label)
        var slider:=HSlider.new();slider.custom_minimum_size=Vector2(280,24);slider.min_value=.25 if key=="zoom" else 0. if key in ["door_angle","fill_power","bounces","ambient"] else -180.;slider.max_value=2. if key in ["zoom","fill_power","ambient"] else 4. if key=="bounces" else 110. if key=="door_angle" else 180.;slider.step=.01 if key in ["zoom","fill_power","ambient"] else 1.;slider.value=state[key]
        slider.value_changed.connect(func(value: float):command({"op":"set_values","values":{key:int(value) if key=="bounces" else value}}));controls[key]=slider;box.add_child(slider)
    for key in ["field_lighting","indirect","key_enabled","fill_enabled","energy_radius","normals","shadows"]:
        var checkbox:=CheckBox.new();checkbox.text={"field_lighting":"Usar campo de luz LIE","indirect":"Luz indirecta","key_enabled":"Luz principal","fill_enabled":"Segunda luz","energy_radius":"Radio energético","normals":"Relieve fino","shadows":"Sombras"}[key];checkbox.button_pressed=state[key];checkbox.toggled.connect(func(value: bool):command({"op":"set_values","values":{key:value}}));box.add_child(checkbox);controls[key]=checkbox
    var button:=Button.new();button.text="Semilla 2102 / 7319";button.pressed.connect(func():command({"op":"set_values","values":{"seed":7319 if state.seed==2102 else 2102}}));box.add_child(button)
    var credit:=Label.new();credit.text="Powered by Poly Haven\nLadrillo: Centre-of-Archaeology\nPerfiles nuevos: autoría LIE";box.add_child(credit)
    light_world=World.new();add_child(light_world);light_world.begin_update();key_emitter=Emitter.new();key_emitter.light_id="key";light_world.add_child(key_emitter);fill_emitter=Emitter.new();fill_emitter.light_id="fill";light_world.add_child(fill_emitter);light_world.end_update();light_world.codes_changed.connect(_accept_light_snapshot)
    var source: Variant=JSON.parse_string(FileAccess.get_file_as_string(effect.scene_root()+"fields/materials.json"))
    if source is Dictionary and source.get("scene_identity")==effect.manifest.scene_identity:_materials=source.get("materials",{})
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
        elif key in ["normals","shadows","occluder","reverse_banks","field_lighting","indirect","key_enabled","fill_enabled","energy_radius"]:
            if not value is bool:return {"ok":false,"error":"boolean"}
        elif key=="bounces":
            if not value is int or value<0 or value>4:return {"ok":false,"error":"bounces"}
        elif key=="lod":
            if not value is int or value< -1 or value>4:return {"ok":false,"error":"lod"}
        elif key in ["yaw","elevation","light","zoom","focus_x","focus_y","door_angle","fill_power","ambient"]:
            if not (value is int or value is float) or not is_finite(float(value)):return {"ok":false,"error":"number"}
            if key in ["fill_power","ambient"] and (value<0 or value>2):return {"ok":false,"error":"power"}
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
    var instances:=PackedFloat32Array();var jobs:=PackedInt32Array();var field_entries: Array=[];work=0
    for i in range(entries.size()):
        var e: Dictionary=entries[i];var bank: int=effect.manifest.banks.find(e.bank);var c: Array=e.basis_columns;var basis:=Basis(Vector3(c[0][0],c[0][1],c[0][2]),Vector3(c[1][0],c[1][1],c[1][2]),Vector3(c[2][0],c[2][1],c[2][2]));var s: Array=e.scale;basis=basis.scaled_local(Vector3(s[0],s[1],s[2]));var p: Array=e.origin;var origin:=Vector3(p[0],p[1],p[2])
        if state.mode=="door" and String(e.id).ends_with("/leaf"):
            var rotation:=Basis(Vector3.UP,deg_to_rad(state.door_angle));origin+=Vector3(-.41,0,0)+rotation*Vector3(.41,0,0);basis=rotation*basis
        var optical_entry: Dictionary=e.duplicate(true);optical_entry.origin=[origin.x,origin.y,origin.z];var rigid:=basis.scaled_local(Vector3(1./s[0],1./s[1],1./s[2]));optical_entry.basis_columns=[[rigid.x.x,rigid.x.y,rigid.x.z],[rigid.y.x,rigid.y.y,rigid.y.z],[rigid.z.x,rigid.z.y,rigid.z.z]];field_entries.append(optical_entry)
        for v in [basis.x,basis.y,basis.z,origin]:instances.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
        var tint: Array=e.tint;var clip: Dictionary=effect.banks[bank].catalog.masters[e.master].get("cut_clip",{})
        instances.append_array(PackedFloat32Array([i*8,bank,clip.get("sense",0),clip.get("plane_m",0),tint[0],tint[1],tint[2],e.roughness_delta]))
        var range_data: Dictionary=effect.banks[bank].catalog.masters[e.master].levels[levels[i]];jobs.append_array(PackedInt32Array([range_data.start,range_data.count,i,work]));work+=int(range_data.count)
    var packet:=PackedFloat32Array()
    for v in [camera.position,camera.basis.x,camera.basis.y,-camera.basis.z]:packet.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    packet.append_array(PackedFloat32Array([tan(deg_to_rad(camera.fov)*.5),1,.0005,100]));var bytes: PackedByteArray=packet.to_byte_array();bytes.append_array(PackedInt32Array([work,entries.size(),effect.render_size,effect.render_size]).to_byte_array())
    var angle: float=deg_to_rad(state.light);var r: float=distance*.8;var light: Vector3=target+Vector3(sin(angle)*r,.9*r,cos(angle)*r);var pose:=Transform3D(Basis.IDENTITY,light).looking_at(target,Vector3.UP)
    var values:=PackedFloat32Array([light.x,light.y,light.z,55*r*r,1,.96,.91,0,.32*state.ambient,.35*state.ambient,.40*state.ambient,1.6,1 if state.shadows else 0,1,.0007,.00022])
    for v in [pose.basis.x,pose.basis.y,-pose.basis.z]:values.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    values.append_array(PackedFloat32Array([1,1,1 if state.reverse_banks else 0,0,1,1,1,0,2102,1,0,1 if state.normals else 0]));bytes.append_array(values.to_byte_array())
    _building=true;light_world.begin_update();key_emitter.position=light;key_emitter.power_rgb_linear=Vector3(1,.96,.91)*55*r*r;key_emitter.radius_m=12.;key_emitter.enabled=state.key_enabled;fill_emitter.position=target+Vector3(r*.7,.6*r,-r*.5);fill_emitter.power_rgb_linear=Vector3(.44,.72,1)*55*r*r*state.fill_power;fill_emitter.radius_m=12.;fill_emitter.enabled=state.fill_enabled;light_world.end_update();_building=false
    if not _configure_field(field_entries,instances.to_byte_array()):metrics={"error":"field source or ownership contract"};return
    metrics={"configured":effect.configure(bytes,instances.to_byte_array(),jobs.to_byte_array(),work),"instances":entries.size(),"work":work,"source_mesh_draws":0,"banks":effect.banks.size()}
func _accept_light_snapshot(snapshot: Dictionary) -> void:
    _last_light_snapshot=snapshot
    if _building or transport==null or light_model.is_empty():return
    light_model.lights=snapshot.lights
    if not transport.gpu_ready or transport.optical_metrics().lights!=snapshot.lights.size():transport.configure(light_model)
    else:transport.set_light_codes(light_model)
func _configure_field(entries: Array,instances: PackedByteArray) -> bool:
    if not state.field_lighting:
        effect.clear_field();world_environment.compositor.compositor_effects=[effect]
        if transport!=null:transport.enabled=false;transport.shutdown();transport=null
        light_model={};_field_geometry="";return true
    var key: String=JSON.stringify([state.mode,state.seed,state.door_angle if state.mode=="door" else 0,state.occluder])
    if key!=_field_geometry or transport==null:
        var data: Dictionary
        if state.mode=="corner":data=Adapter.load_corner(effect.scene_root()+"fields/corner-"+str(state.seed)+"/",effect.scene_root()+"corner-"+str(state.seed)+".json",effect.manifest.scene_identity)
        else:data=Adapter.small_scene(entries,_materials)
        if data.is_empty():return false
        var next: CompositorEffect=Field.new();var model: Dictionary=data.model;model.lights=light_world.render_snapshot().lights;model.bounces=state.bounces
        if state.energy_radius:model.secondary_radii={"mode":"irradiance","radius_max":12.,"radius_decay":.8,"irradiance_cutoff":.01}
        if not next.bind_sources(model,data.sources) or not next.configure(model):next.shutdown();return false
        next.set_direct_shadow_enabled(state.shadows)
        if not effect.bind_field(next,data.mapping,instances,effect.manifest.scene_identity,state.indirect,light_world.render_snapshot().ids.find("key")):next.shutdown();return false
        var previous: CompositorEffect=transport;transport=next;light_model=model;_field_geometry=key;transport.set_meta("mapping",data.mapping);world_environment.compositor.compositor_effects=[transport,effect]
        if previous!=null:previous.enabled=false;previous.shutdown()
    else:
        var changed: bool=light_model.bounces!=state.bounces or light_model.has("secondary_radii")!=state.energy_radius
        light_model.lights=light_world.render_snapshot().lights;light_model.bounces=state.bounces
        if state.energy_radius:light_model.secondary_radii={"mode":"irradiance","radius_max":12.,"radius_decay":.8,"irradiance_cutoff":.01}
        else:light_model.erase("secondary_radii")
        if changed or not transport.gpu_ready or transport.optical_metrics().lights!=light_model.lights.size():
            if not transport.configure(light_model):return false
        else:transport.set_light_codes(light_model)
        transport.set_direct_shadow_enabled(state.shadows)
        if not effect.bind_field(transport,transport.get_meta("mapping"),instances,effect.manifest.scene_identity,state.indirect,light_world.render_snapshot().ids.find("key")):return false
    return true
func _process(_delta: float) -> void:
    if effect.gpu_ready and texture==null:texture=Texture2DRD.new();texture.texture_rd_rid=effect.output_rid;picture.texture=texture
func _exit_tree() -> void:
    if texture!=null:texture.texture_rd_rid=RID()
    if effect!=null:effect.shutdown()
    if transport!=null:transport.enabled=false;transport.shutdown()
