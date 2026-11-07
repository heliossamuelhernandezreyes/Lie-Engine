extends Node3D
const Effect=preload("res://lie_hq_material_effect.gd")
const MATERIALS=["concrete_layers","wood_table_worn","rock_boulder_dry","grey_plaster"]
var effect: CompositorEffect
var camera: Camera3D
var world_environment: WorldEnvironment
var picture: TextureRect
var texture: Texture2DRD
var state: Dictionary={"material":"concrete_layers","yaw":0.,"elevation":0.,"light":-35.,"zoom":1.,"lod":0,"assembly":false}
var revision: int=0
var metrics: Dictionary={}
var selector: OptionButton
var controls: Dictionary={}
func _ready() -> void:
    camera=Camera3D.new();add_child(camera);camera.current=true
    world_environment=WorldEnvironment.new();add_child(world_environment);world_environment.environment=Environment.new();world_environment.compositor=Compositor.new()
    var layer:=CanvasLayer.new();add_child(layer);var bg:=ColorRect.new();bg.color=Color(.035,.04,.05);bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layer.add_child(bg)
    picture=TextureRect.new();picture.position=Vector2(10,10);picture.size=Vector2(760,760);layer.add_child(picture)
    var title:=Label.new();title.position=Vector2(790,20);title.text="LIE · MATERIALES FOTOGRÁFICOS\n\nOriginales 8K · CC0\nPowered by Poly Haven\n\nRelieve geométrico, color y rugosidad\nParche físico de 32 × 32 cm\nSin malla fuente en el render\n\nNormal óptica original: conservada,\naún sin consumir en el formato 80B.\n\nEstos recortes no son repetibles\nsin costura ni objetos completos.";layer.add_child(title)
    selector=OptionButton.new();selector.position=Vector2(790,340);selector.size=Vector2(290,36)
    for material in MATERIALS:selector.add_item(material.replace("_"," "))
    selector.item_selected.connect(func(i: int):command({"op":"set_values","values":{"material":MATERIALS[i]}}));layer.add_child(selector)
    var y: int=400
    for key in ["yaw","elevation","light","zoom"]:
        var label:=Label.new();label.text=key;label.position=Vector2(790,y);layer.add_child(label)
        var slider:=HSlider.new();slider.position=Vector2(790,y+25);slider.size=Vector2(280,24);slider.min_value=.7 if key=="zoom" else -65.;slider.max_value=1.5 if key=="zoom" else 65.;slider.step=.01 if key=="zoom" else 1.;slider.value=state[key];controls[key]=slider
        slider.value_changed.connect(func(v: float):command({"op":"set_values","values":{key:v}}));layer.add_child(slider);y+=70
    switch_bank();update_scene()
func switch_bank() -> void:
    if texture!=null:texture.texture_rd_rid=RID();texture=null;picture.texture=null
    if effect!=null:
        world_environment.compositor.compositor_effects=[];effect.shutdown()
    effect=Effect.new(state.material,1024);world_environment.compositor.compositor_effects=[effect]
func command(request: Dictionary) -> Dictionary:
    if request.get("op")=="snapshot":return {"ok":true,"state":state.duplicate(),"revision":revision,"metrics":metrics.duplicate()}
    if request.get("op")!="set_values" or not request.get("values") is Dictionary:return {"ok":false,"error":"command"}
    if request.has("expected_revision") and (not request.expected_revision is int or request.expected_revision!=revision):return {"ok":false,"error":"revision"}
    var candidate: Dictionary=state.duplicate()
    for key in request.values:
        var value: Variant=request.values[key]
        if key=="material":
            if not value is String or value not in MATERIALS:return {"ok":false,"error":"material"}
        elif key=="lod":
            if not value is int or value<0 or value>2:return {"ok":false,"error":"lod"}
        elif key=="assembly":
            if not value is bool:return {"ok":false,"error":"assembly"}
        elif key in ["yaw","elevation","light","zoom"]:
            if not (value is int or value is float) or not is_finite(float(value)):return {"ok":false,"error":"number"}
            if (key=="zoom" and (value<.7 or value>1.5)) or (key!="zoom" and abs(value)>65):return {"ok":false,"error":"range"}
        else:return {"ok":false,"error":"key"}
        candidate[key]=value
    var changed: bool=candidate.material!=state.material;state=candidate;revision+=1
    if changed:switch_bank()
    update_scene();return {"ok":true,"revision":revision}
func update_scene() -> void:
    selector.select(MATERIALS.find(state.material))
    for key in controls:controls[key].set_value_no_signal(state[key])
    var recipe: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(effect.capture_root()+("quartet.json" if state.assembly else "panel.json")))
    if recipe.bank_sha256!=effect.catalog.sha256:metrics={"error":"set_bank_identity"};return
    var target:=Vector3.ZERO;var extent: float=maxf(float(recipe.bounds_m[0]),float(recipe.bounds_m[1]));var distance: float=extent*1.8*state.zoom
    var yaw: float=deg_to_rad(state.yaw);var elevation: float=deg_to_rad(state.elevation)
    camera.fov=42;camera.position=Vector3(sin(yaw)*cos(elevation),sin(elevation),cos(yaw)*cos(elevation))*distance;camera.look_at(target)
    var packet:=PackedFloat32Array()
    for v in [camera.position,camera.basis.x,camera.basis.y,-camera.basis.z]:packet.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    packet.append_array(PackedFloat32Array([tan(deg_to_rad(camera.fov)*.5),1,.0005,100]))
    var count: int=recipe.instances.size();var level: int=1 if state.assembly else state.lod;var range_data: Dictionary=effect.catalog.masters[state.material].levels[level];var work: int=count*int(range_data.count)
    var bytes: PackedByteArray=packet.to_byte_array();bytes.append_array(PackedInt32Array([work,count,effect.render_size,effect.render_size]).to_byte_array())
    var angle: float=deg_to_rad(state.light);var r: float=distance*.7;var light:=Vector3(sin(angle)*r,r*.9,cos(angle)*r);var pose:=Transform3D(Basis.IDENTITY,light).looking_at(target,Vector3.UP)
    # Fixed relightable GGX, no baked AO; shadows disabled for calibrated comparisons.
    var values:=PackedFloat32Array([light.x,light.y,light.z,55*r*r,1,.96,.91,0,.27,.30,.36,1.6,0,1,.0004,.00012])
    for v in [pose.basis.x,pose.basis.y,-pose.basis.z]:values.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    values.append_array(PackedFloat32Array([1,1,1,0,1,1,1,0,2102,1,0,0]));bytes.append_array(values.to_byte_array())
    var instances:=PackedFloat32Array();var jobs:=PackedInt32Array()
    for i in range(count):
        var entry: Dictionary=recipe.instances[i];var a: Array=entry.origin;var c: Array=entry.basis_columns
        var origin:=Vector3(a[0],a[1],a[2]);var basis:=Basis(Vector3(c[0][0],c[0][1],c[0][2]),Vector3(c[1][0],c[1][1],c[1][2]),Vector3(c[2][0],c[2][1],c[2][2]))
        for v in [basis.x,basis.y,basis.z,origin]:instances.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
        instances.append_array(PackedFloat32Array([i*8,0,0,0,1,1,1,0]));jobs.append_array(PackedInt32Array([range_data.start,range_data.count,i,i*range_data.count]))
    metrics={"configured":effect.configure(bytes,instances.to_byte_array(),jobs.to_byte_array(),work),"instances":count,"samples":work,"source_mesh_draws":0,"bank_sha256":effect.catalog.sha256}
func _process(_delta: float) -> void:
    if effect.gpu_ready and texture==null:texture=Texture2DRD.new();texture.texture_rd_rid=effect.output_rid;picture.texture=texture
func _exit_tree() -> void:
    if texture!=null:texture.texture_rd_rid=RID()
    if effect!=null:effect.shutdown()
