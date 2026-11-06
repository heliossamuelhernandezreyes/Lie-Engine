extends Node3D
const Effect=preload("res://lie_scanned_masonry_effect.gd")
var effect: CompositorEffect
var camera: Camera3D
var world_environment: WorldEnvironment
var picture: TextureRect
var texture: Texture2DRD
var state: Dictionary={"mode":"brick","seed":2102,"yaw":30.0,"elevation":24.0,"light":-35.0,"roof":true}
var revision: int=0
var metrics: Dictionary={}
var recipe: Dictionary={}
func _ready() -> void:
    effect=Effect.new(720);camera=Camera3D.new();add_child(camera);camera.current=true
    world_environment=WorldEnvironment.new();add_child(world_environment);world_environment.environment=Environment.new();world_environment.compositor=Compositor.new();world_environment.compositor.compositor_effects=[effect]
    var layer:=CanvasLayer.new();add_child(layer);var bg:=ColorRect.new();bg.color=Color(.028,.035,.045);bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layer.add_child(bg)
    picture=TextureRect.new();picture.position=Vector2(10,10);picture.size=Vector2(720,720);layer.add_child(picture)
    var title:=Label.new();title.position=Vector2(744,20);title.text="LIE · LADRILLO ESCANEADO\n\n500 000 triángulos de origen\nCapturas con volumen real\nCOLOR_0 original · rugosidad 0.6\n\nSemillas reproducibles\nLadrillo → muro → casa\nSin malla original en cámara\n\nPrototipo de aparejo apilado\nMortero y techo: autoría simple\nIluminación GGX + ambiente\nGI compartida aún pendiente";layer.add_child(title)
    var row:=HBoxContainer.new();row.position=Vector2(744,300);layer.add_child(row)
    for mode in ["brick","wall","house"]:
        var button:=Button.new();button.text=mode;button.pressed.connect(func():command({"op":"set_values","values":{"mode":mode}}));row.add_child(button)
    var next:=Button.new();next.position=Vector2(744,350);next.text="Semilla 2102 / 7319";next.pressed.connect(func():command({"op":"set_values","values":{"seed":7319 if state.seed==2102 else 2102}}));layer.add_child(next)
    var roof:=Button.new();roof.position=Vector2(744,395);roof.text="Mostrar / quitar techo";roof.pressed.connect(func():command({"op":"set_values","values":{"roof":not state.roof}}));layer.add_child(roof)
    update_scene()
func command(request: Dictionary) -> Dictionary:
    if request.get("op")=="snapshot":return {"ok":true,"snapshot":agent_snapshot()}
    if request.get("op")!="set_values" or not request.get("values") is Dictionary:return {"ok":false,"error":"command"}
    if request.has("expected_revision") and (not request.expected_revision is int or request.expected_revision!=revision):return {"ok":false,"error":"revision"}
    var candidate: Dictionary=state.duplicate()
    for key in request.values:
        var value: Variant=request.values[key]
        if key=="mode":
            if not value is String or value not in ["brick","wall","house"]:return {"ok":false,"error":"mode"}
        elif key=="seed":
            if not value is int or value not in [2102,7319]:return {"ok":false,"error":"precompiled_seed"}
        elif key=="roof":
            if not value is bool:return {"ok":false,"error":"roof"}
        elif key in ["yaw","elevation","light"]:
            if not (value is int or value is float) or not is_finite(float(value)) or abs(float(value))>180:return {"ok":false,"error":"angle"}
        else:return {"ok":false,"error":"key"}
        candidate[key]=value
    state=candidate;revision+=1;update_scene();return {"ok":true,"revision":revision}
func update_scene() -> void:
    recipe=JSON.parse_string(FileAccess.get_file_as_string(effect.capture_root()+state.mode+"-"+str(state.seed)+".json"))
    if recipe.bank_sha256!=effect.catalog.sha256:metrics={"error":"recipe_bank_identity"};return
    var b: Array=recipe.bounds_m;var extent: float=maxf(float(b[0]),maxf(float(b[1]),float(b[2])));var target:=Vector3(0,0 if state.mode=="brick" else float(b[1])*.5,0)
    camera.fov=42;var distance: float=extent*2.05;var yaw: float=deg_to_rad(state.yaw);var elevation: float=deg_to_rad(state.elevation)
    camera.position=target+Vector3(sin(yaw)*cos(elevation),sin(elevation),cos(yaw)*cos(elevation))*distance;camera.look_at(target)
    var entries: Array=[]
    for entry in recipe.instances:
        if entry.id=="roof" and not state.roof:continue
        entries.append(entry)
    var levels: Array=[];var work: int=0
    for entry in entries:
        var level: int=0 if state.mode=="brick" else 2 if state.mode=="wall" else 3
        if entry.id in ["roof","floor"]:level=0
        levels.append(level);work+=int(effect.catalog.masters[entry.master].levels[level].count)
    # Deterministic budget fallback, never an unchecked allocation.
    while work>effect.work_capacity():
        var changed: bool=false
        for i in range(entries.size()):
            var ranges: Array=effect.catalog.masters[entries[i].master].levels;var level: int=levels[i]
            if level+1<ranges.size():work-=int(ranges[level].count)-int(ranges[level+1].count);levels[i]+=1;changed=true
            if work<=effect.work_capacity():break
        if not changed:metrics={"error":"sample_budget"};return
    var instance_data:=PackedFloat32Array();var jobs:=PackedInt32Array();work=0
    for i in range(entries.size()):
        var entry: Dictionary=entries[i];var a: Array=entry.origin;var s: Array=entry.scale;var basis:=Basis(Vector3.UP,float(entry.yaw)).scaled_local(Vector3(s[0],s[1],s[2]));var origin:=Vector3(a[0],a[1],a[2])
        for v in [basis.x,basis.y,basis.z,origin]:instance_data.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
        instance_data.append_array(PackedFloat32Array([i*8,0,0,0,1,1,1,0]))
        var range_data: Dictionary=effect.catalog.masters[entry.master].levels[levels[i]];jobs.append_array(PackedInt32Array([range_data.start,range_data.count,i,work]));work+=int(range_data.count)
    var packet:=PackedFloat32Array()
    for v in [camera.position,camera.basis.x,camera.basis.y,-camera.basis.z]:packet.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    packet.append_array(PackedFloat32Array([tan(deg_to_rad(camera.fov)*.5),1,.0005,100]))
    var bytes: PackedByteArray=packet.to_byte_array();bytes.append_array(PackedInt32Array([work,entries.size(),effect.render_size,effect.render_size]).to_byte_array())
    var angle: float=deg_to_rad(state.light);var r: float=distance*.7;var light: Vector3=target+Vector3(sin(angle)*r,r*.9,cos(angle)*r);var pose:=Transform3D(Basis.IDENTITY,light).looking_at(target,Vector3.UP)
    var spacing: float=.0008 if state.mode=="brick" else .003
    var values:=PackedFloat32Array([light.x,light.y,light.z,55*r*r,1,.96,.91,0,.27,.30,.36,1.6,1,1,spacing,spacing*.3])
    for v in [pose.basis.x,pose.basis.y,-pose.basis.z]:values.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    values.append_array(PackedFloat32Array([1,1,1,0,1,1,1,0,2102,1,0,0]));bytes.append_array(values.to_byte_array())
    metrics={"configured":effect.configure(bytes,instance_data.to_byte_array(),jobs.to_byte_array(),work),"instances":entries.size(),"samples":work,"bank_sha256":effect.catalog.sha256,"original_mesh_draws":0}
func agent_snapshot() -> Dictionary:return {"state":state.duplicate(),"revision":revision,"metrics":metrics.duplicate(),"gpu_ready":effect.gpu_ready,"failure":effect.failure,"controls":{"modes":["brick","wall","house"],"precompiled_seeds":[2102,7319],"angles":[-180,180],"roof":"boolean"}}
func _process(_delta: float) -> void:
    if effect.gpu_ready and texture==null:texture=Texture2DRD.new();texture.texture_rd_rid=effect.output_rid;picture.texture=texture
func _exit_tree() -> void:
    if texture!=null:texture.texture_rd_rid=RID()
    if effect!=null:effect.shutdown()
