extends Node3D
## Native, reproducible matte laboratory. All controls use command().
const Transport=preload("res://lie_brick_reference_transport.gd")
const Effect=preload("res://lie_brick_reference_effect.gd")
const Loader=preload("res://lie_light_field_loader.gd")
const QualityModel=preload("res://lie_field_quality_model.gd")
const ROOT="res://captures/brick_reference/"
var manifest: Dictionary={}
var state: Dictionary={"case":"matte_point","mode":"total","improved":true,"power":1.0,"radius":false}
var revision: int=0
var failure: String=""
var transport: CompositorEffect
var effect: CompositorEffect
var camera: Camera3D
var world: WorldEnvironment
var texture: Texture2DRD
var picture: TextureRect
var reference_picture: TextureRect
var case_control: OptionButton
var improved_control: CheckBox
var radius_control: CheckBox
var power_control: HSlider
var status: Label
var model: Dictionary={}
var current: Dictionary={}
var ui_enabled: bool=true
func xyz(a: Array) -> Vector3:return Vector3(a[0],a[1],a[2])
func _ready() -> void:
    var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"manifest.json"))
    if not parsed is Dictionary or parsed.get("schema")!="lie-brick-reference/1":failure="Generate the shared source and Cycles references first";return
    manifest=parsed
    world=WorldEnvironment.new();var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color.BLACK;world.environment=environment;add_child(world)
    camera=Camera3D.new();camera.current=true;camera.position=xyz(manifest.camera.eye);camera.fov=manifest.camera.vertical_fov_degrees;camera.near=.001;camera.far=40;add_child(camera);camera.look_at(xyz(manifest.camera.target))
    if ui_enabled:_ui()
    _install_case()
func _clear() -> void:
    if texture!=null:texture.texture_rd_rid=RID();texture=null
    if world!=null:world.compositor=null
    # Consumer releases its borrowed descriptors before the field owner.
    if effect!=null:effect.shutdown();effect=null
    if transport!=null:transport.shutdown();transport=null
func _install_case() -> void:
    _clear()
    for row in manifest.cases:
        if row.name==state.case:current=row.duplicate(true);break
    var root: String=ROOT+state.case+"/"
    model=JSON.parse_string(FileAccess.get_file_as_string(root+"light-model.json"))
    model["emission_descriptors"]=str(current.emission_hex).hex_decode()
    transport=Transport.new()
    if not transport.bind_sources(model,Loader.load_sources(root)):failure="Source field identity";return
    effect=Effect.new(int(manifest.resolution));effect.transport=transport
    var floats:=PackedFloat32Array();floats.resize(24*4)
    for i in range(model.lights.size()):
        var pose:=Transform3D(Basis.IDENTITY,xyz(model.lights[i].position)).looking_at(xyz(manifest.camera.target),Vector3.UP)
        for row in [[pose.basis.x,0],[pose.basis.y,1],[-pose.basis.z,2]]:
            var at: int=(i*3+row[1])*4;floats[at]=row[0].x;floats[at+1]=row[0].y;floats[at+2]=row[0].z
    for i in range(model.patches.size()):
        var p: Dictionary=model.patches[i];var group: Array=current.groups[i]
        floats.append_array(PackedFloat32Array(p.position+[p.area]+p.normal+[0.]+[float(group[0]),float(group[1]),0.,0.]))
    effect.bench_packet=PackedInt32Array([model.patches.size(),model.lights.size(),0,0]).to_byte_array();effect.bench_packet.append_array(floats.to_byte_array())
    var compositor:=Compositor.new()
    compositor.compositor_effects=[transport] if OS.get_environment("LIE_BRICK_FIELD_ONLY")=="1" else [transport,effect]
    world.compositor=compositor
    _apply()
func _apply() -> void:
    if effect==null:return
    var physical: Dictionary=model.duplicate(true)
    for light in physical.lights:light.power_rgb=light.power_rgb.map(func(v):return v*state.power)
    physical.field_quality={"angular_sectors":6 if state.improved else 1,"area_budget":state.improved}
    if state.radius:physical.secondary_radii={"mode":"irradiance","radius_max":2.,"radius_decay":1.,"irradiance_cutoff":.001}
    if not transport.configure(physical):failure="Field configuration";return
    var instance_data:=PackedFloat32Array();var jobs:=PackedInt32Array();var work: int=0
    for i in range(current.instances.size()):
        var inst: Dictionary=current.instances[i];var meta: Dictionary=effect.catalog.masters[inst.master];var level: Dictionary=meta.levels[0]
        for v in [Vector3.RIGHT,Vector3.UP,Vector3.BACK,xyz(inst.position)]:instance_data.append_array(PackedFloat32Array([v.x,v.y,v.z,0.]))
        instance_data.append_array(PackedFloat32Array([float(inst.node_offset),0.,0.,0.,1.,1.,1.,1.]))
        jobs.append_array(PackedInt32Array([level.start,level.count,i,work]));work+=int(level.count)
    var packet:=PackedFloat32Array()
    for v in [camera.position,camera.basis.x,camera.basis.y,-camera.basis.z]:packet.append_array(PackedFloat32Array([v.x,v.y,v.z,0.]))
    packet.append_array(PackedFloat32Array([tan(deg_to_rad(camera.fov)*.5),1.,.001,40.]))
    var bytes: PackedByteArray=packet.to_byte_array();bytes.append_array(PackedInt32Array([work,current.instances.size(),effect.render_size,effect.render_size]).to_byte_array())
    packet=PackedFloat32Array();packet.resize(40)
    packet[8]=0.;packet[9]=0.;packet[10]=0.;packet[11]=1. # no ambient, exposure exactly 1
    packet[12]=1.;packet[13]=1.;packet[14]=.00025;packet[15]=.0004
    packet[35]=0.;packet[36]=0.;packet[37]=1.;packet[38]=0.;packet[39]=["total","direct","indirect"].find(state.mode)
    bytes.append_array(packet.to_byte_array())
    if not effect.configure(bytes,instance_data.to_byte_array(),jobs.to_byte_array(),work):failure="Capture configuration"
    if reference_picture!=null:
        var image:=Image.load_from_file(ROOT+state.case+"/reference-"+state.mode+".png")
        reference_picture.texture=ImageTexture.create_from_image(image)
        for i in range(case_control.item_count):
            if case_control.get_item_metadata(i)==state.case:case_control.select(i)
        improved_control.set_pressed_no_signal(state.improved);radius_control.set_pressed_no_signal(state.radius);power_control.set_value_no_signal(state.power)
func command(request: Variant) -> Dictionary:
    if not request is Dictionary:return {"ok":false,"error":"request"}
    if request.has("expected_revision") and (not QualityModel.integer_value(request.expected_revision,0,0xffffffff) or request.expected_revision!=revision):return {"ok":false,"error":"revision","revision":revision}
    if request.get("op")=="snapshot":return {"ok":true,"snapshot":agent_snapshot()}
    if request.get("op")!="set_values" or not request.get("values") is Dictionary or request.values.is_empty():return {"ok":false,"error":"values"}
    var next: Dictionary=state.duplicate(true)
    for key in request.values:
        if not next.has(key):return {"ok":false,"error":"field"}
        next[key]=request.values[key]
    var names: Array=manifest.cases.map(func(v):return v.name)
    if next.case not in names or next.mode not in ["total","direct","indirect"] or not next.improved is bool or not next.radius is bool:return {"ok":false,"error":"policy"}
    if not (next.power is int or next.power is float) or not is_finite(float(next.power)) or next.power<0 or next.power>4:return {"ok":false,"error":"power"}
    if next!=state:
        var changed: bool=next.case!=state.case;state=next;revision+=1
        if changed:_install_case()
        else:_apply()
    return {"ok":failure.is_empty(),"revision":revision,"error":failure}
func agent_snapshot() -> Dictionary:
    return {"state":state.duplicate(true),"revision":revision,"runtime":{"capture_loaded":effect!=null and effect.capture_loaded,"gpu_ready":effect!=null and effect.gpu_ready and transport!=null and transport.gpu_ready,"failure":failure},"metrics":{"original_mesh_draws":0,"field_visibility_source_triangles":model.get("triangles",[]).size(),"bank_sha256":manifest.get("bank_sha256",""),"field_nodes":current.get("field_nodes",0)},"control_contract":{"commands":["snapshot","set_values"],"cases":manifest.get("cases",[]).map(func(v):return v.name),"modes":["total","direct","indirect"],"power":[0,4],"booleans":["improved","radius"]}}
func _ui() -> void:
    var ui:=CanvasLayer.new();add_child(ui);var box:=VBoxContainer.new();box.position=Vector2(15,68);box.custom_minimum_size=Vector2(245,0);ui.add_child(box)
    var title:=Label.new();title.position=Vector2(15,15);title.text="LIE · LADRILLO / REFERENCIA INDEPENDIENTE";ui.add_child(title)
    case_control=OptionButton.new();case_control.clip_text=true
    var names: Dictionary={"calibration_plane":"Plano de calibración","matte_point":"Ladrillo mate","grazing_point":"Luz rasante","two_bricks":"Dos ladrillos","blocker_left":"Obstáculo a izquierda","blocker_right":"Obstáculo a derecha","area_panel":"Panel de área","wall_opening":"Abertura en pared"}
    for row in manifest.cases:
        case_control.add_item(names.get(row.name,row.name));case_control.set_item_metadata(case_control.item_count-1,row.name)
    case_control.item_selected.connect(func(i):command({"op":"set_values","values":{"case":manifest.cases[i].name}}));box.add_child(case_control)
    for mode in ["total","direct","indirect"]:
        var button:=Button.new();button.text={"total":"Total","direct":"Directa","indirect":"Rebotes"}[mode];button.pressed.connect(func():command({"op":"set_values","values":{"mode":mode}}));box.add_child(button)
    improved_control=CheckBox.new();improved_control.text="Transporte mejorado";improved_control.toggled.connect(func(v):command({"op":"set_values","values":{"improved":v}}));box.add_child(improved_control)
    radius_control=CheckBox.new();radius_control.text="Radio energético";radius_control.toggled.connect(func(v):command({"op":"set_values","values":{"radius":v}}));box.add_child(radius_control)
    var power_label:=Label.new();power_label.text="Potencia de LIE (0–4)";box.add_child(power_label)
    power_control=HSlider.new();power_control.min_value=0.;power_control.max_value=4.;power_control.step=.05;power_control.value_changed.connect(func(v):command({"op":"set_values","values":{"power":v}}));box.add_child(power_control)
    picture=TextureRect.new();picture.position=Vector2(290,80);picture.size=Vector2(440,440);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;ui.add_child(picture)
    reference_picture=TextureRect.new();reference_picture.position=Vector2(760,80);reference_picture.size=Vector2(440,440);reference_picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;ui.add_child(reference_picture)
    for label in [["LIE · capturas + campo",Vector2(290,50)],["Cycles · referencia independiente",Vector2(760,50)]]:
        var item:=Label.new();item.text=label[0];item.position=label[1];ui.add_child(item)
    var shader:=Shader.new();shader.code="shader_type canvas_item; void fragment(){vec4 c=texture(TEXTURE,UV);vec3 x=max(c.rgb,vec3(0));x=x/(vec3(1)+x);COLOR=vec4(mix(x*12.92,1.055*pow(x,vec3(1.0/2.4))-.055,step(vec3(.0031308),x)),c.a);}"
    var material:=ShaderMaterial.new();material.shader=shader;picture.material=material
    status=Label.new();status.position=Vector2(15,380);status.custom_minimum_size.x=245;status.size.x=245;status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;ui.add_child(status)
func _process(_delta: float) -> void:
    if picture!=null and texture==null and effect!=null and effect.gpu_ready:
        texture=Texture2DRD.new();texture.texture_rd_rid=effect.output_rid;picture.texture=texture
    if status!=null:status.text="%s\n%s\nOriginales dibujados en LIE: 0\nMaterial Lambert de control\nVista con Reinhard\nReferencia: potencia 1, sin recorte"%[state.case,failure]
func _exit_tree() -> void:_clear()
