extends Node3D
const Effect=preload("res://lie_scanned_masonry_effect.gd")
var effect: CompositorEffect
var camera: Camera3D
var world_environment: WorldEnvironment
var picture: TextureRect
var texture: Texture2DRD
var mode_control: OptionButton
var zoom_control: HSlider
var state: Dictionary={"mode":"brick","seed":2102,"yaw":30.0,"elevation":24.0,"light":-35.0,"roof":true,"style":"varied","face":0,"zoom":1.0,"focus_x":0.0,"focus_y":0.0}
var revision: int=0
var metrics: Dictionary={}
var recipe: Dictionary={}
func _ready() -> void:
    effect=Effect.new(720);camera=Camera3D.new();add_child(camera);camera.current=true
    world_environment=WorldEnvironment.new();add_child(world_environment);world_environment.environment=Environment.new();world_environment.compositor=Compositor.new();world_environment.compositor.compositor_effects=[effect]
    var layer:=CanvasLayer.new();add_child(layer);var bg:=ColorRect.new();bg.color=Color(.028,.035,.045);bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layer.add_child(bg)
    picture=TextureRect.new();picture.position=Vector2(10,10);picture.size=Vector2(720,720);layer.add_child(picture)
    var title:=Label.new();title.position=Vector2(744,20);title.text="LIE · LADRILLO ESCANEADO\n\n500 000 triángulos de origen\nCapturas con volumen real\nCOLOR_0 original + tono por pieza\n\nSemillas reproducibles\nLadrillo → muro → casa\nSin malla original en cámara\n\n"+("Aparejo alternado · cuatro giros\nMedios ladrillos: corte real" if effect.catalog.has("assembly_version") else "Prototipo de aparejo apilado\nMortero y techo: autoría simple")+"\nIluminación GGX + ambiente\nGI compartida aún pendiente";layer.add_child(title)
    mode_control=OptionButton.new();mode_control.position=Vector2(744,300);mode_control.size=Vector2(310,38);layer.add_child(mode_control)
    for mode in mode_options():mode_control.add_item({"brick":"Ladrillo","wall":"Muro con juntas","house":"Casa","kit":"Banco de piezas","frame":"Conjunto de abertura","roof":"Conjunto de cubierta"}.get(mode,mode.trim_prefix("asset_").replace("_"," ")))
    mode_control.item_selected.connect(func(index: int):command({"op":"set_values","values":{"mode":mode_options()[index]}}))
    var next:=Button.new();next.position=Vector2(744,350);next.text="Semilla 2102 / 7319";next.pressed.connect(func():command({"op":"set_values","values":{"seed":7319 if state.seed==2102 else 2102}}));layer.add_child(next)
    var roof:=Button.new();roof.position=Vector2(744,395);roof.text="Mostrar / quitar techo";roof.pressed.connect(func():command({"op":"set_values","values":{"roof":not state.roof}}));layer.add_child(roof)
    if effect.catalog.has("assembly_version"):
        var styles:=VBoxContainer.new();styles.position=Vector2(744,450);layer.add_child(styles)
        for choice in ["varied","uniform","legacy"]:
            var button:=Button.new();button.text={"varied":"Caras y tonos variados","uniform":"Intercalado sin variación","legacy":"Construcción anterior"}[choice];button.pressed.connect(func():command({"op":"set_values","values":{"style":choice}}));styles.add_child(button)
        var face:=Button.new();face.position=Vector2(744,590);face.text="Girar ladrillo / otra cara";face.pressed.connect(func():command({"op":"set_values","values":{"mode":"brick","face":(state.face+1)%4}}));layer.add_child(face)
    var zoom_label:=Label.new();zoom_label.position=Vector2(744,640);zoom_label.text="Distancia de inspección";layer.add_child(zoom_label)
    zoom_control=HSlider.new();zoom_control.position=Vector2(744,670);zoom_control.size=Vector2(300,30);zoom_control.min_value=.35;zoom_control.max_value=2.;zoom_control.step=.05;zoom_control.value=1.;zoom_control.value_changed.connect(func(value: float):command({"op":"set_values","values":{"zoom":value}}));layer.add_child(zoom_control)
    update_scene()
func mode_options() -> Array:return ["brick","wall","house"]+effect.catalog.get("kit_modes",[])
func recipe_path(candidate: Dictionary) -> String:
    if candidate.mode in effect.catalog.get("kit_modes",[]):return effect.capture_root()+candidate.mode+"-"+str(candidate.seed)+".json"
    if candidate.mode=="brick" and candidate.face>0:return effect.capture_root()+"brick-face-"+str(candidate.face)+"-"+str(candidate.seed)+".json"
    var suffix: String="" if candidate.style=="varied" else "-"+candidate.style
    return effect.capture_root()+candidate.mode+suffix+"-"+str(candidate.seed)+".json"
func command(request: Dictionary) -> Dictionary:
    if request.get("op")=="snapshot":return {"ok":true,"snapshot":agent_snapshot()}
    if request.get("op")!="set_values" or not request.get("values") is Dictionary:return {"ok":false,"error":"command"}
    if request.has("expected_revision") and (not request.expected_revision is int or request.expected_revision!=revision):return {"ok":false,"error":"revision"}
    var candidate: Dictionary=state.duplicate()
    for key in request.values:
        var value: Variant=request.values[key]
        if key=="mode":
            if not value is String or value not in mode_options():return {"ok":false,"error":"mode"}
        elif key=="seed":
            if not value is int or value not in [2102,7319]:return {"ok":false,"error":"precompiled_seed"}
        elif key=="roof":
            if not value is bool:return {"ok":false,"error":"roof"}
        elif key=="style":
            if not value is String or value not in ["varied","uniform","legacy"]:return {"ok":false,"error":"style"}
        elif key=="face":
            if not value is int or value<0 or value>3:return {"ok":false,"error":"face"}
        elif key in ["yaw","elevation","light"]:
            if not (value is int or value is float) or not is_finite(float(value)) or abs(float(value))>180:return {"ok":false,"error":"angle"}
        elif key in ["zoom","focus_x","focus_y"]:
            if not (value is int or value is float) or not is_finite(float(value)):return {"ok":false,"error":"camera"}
            if key=="zoom" and (float(value)<.35 or float(value)>2.):return {"ok":false,"error":"zoom"}
            if key!="zoom" and abs(float(value))>10:return {"ok":false,"error":"focus"}
        else:return {"ok":false,"error":"key"}
        candidate[key]=value
    if not FileAccess.file_exists(recipe_path(candidate)):return {"ok":false,"error":"recipe_unavailable"}
    state=candidate;revision+=1;update_scene();return {"ok":true,"revision":revision}
func update_scene() -> void:
    recipe=JSON.parse_string(FileAccess.get_file_as_string(recipe_path(state)))
    mode_control.select(mode_options().find(state.mode))
    zoom_control.set_value_no_signal(state.zoom)
    if recipe.bank_sha256!=effect.catalog.sha256:metrics={"error":"recipe_bank_identity"};return
    var b: Array=recipe.bounds_m;var extent: float=maxf(float(b[0]),maxf(float(b[1]),float(b[2])));var target:=Vector3(0,0 if state.mode=="brick" else float(b[1])*.5,0)
    target+=Vector3(state.focus_x,state.focus_y,0)
    camera.fov=42;var distance: float=extent*2.05*state.zoom;var yaw: float=deg_to_rad(state.yaw);var elevation: float=deg_to_rad(state.elevation)
    camera.position=target+Vector3(sin(yaw)*cos(elevation),sin(elevation),cos(yaw)*cos(elevation))*distance;camera.look_at(target)
    var entries: Array=[]
    for entry in recipe.instances:
        if String(entry.id).get_file()=="roof" and not state.roof:continue
        entries.append(entry)
    var levels: Array=[];var work: int=0
    for entry in entries:
        var level: int=0 if state.mode=="brick" else 2 if state.mode=="wall" else 3
        level=int(entry.get("lod",level))
        if String(entry.id).get_file() in ["roof","floor"]:level=0
        if level<0 or level>=effect.catalog.masters[entry.master].levels.size():metrics={"error":"asset_lod"};return
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
        var entry: Dictionary=entries[i];var a: Array=entry.origin;var s: Array=entry.scale;var basis:=Basis(Vector3.UP,float(entry.yaw));var origin:=Vector3(a[0],a[1],a[2])
        if entry.has("basis_columns"):
            var c: Array=entry.basis_columns;basis=Basis(Vector3(c[0][0],c[0][1],c[0][2]),Vector3(c[1][0],c[1][1],c[1][2]),Vector3(c[2][0],c[2][1],c[2][2]))
        basis=basis.scaled_local(Vector3(s[0],s[1],s[2]))
        for v in [basis.x,basis.y,basis.z,origin]:instance_data.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
        var tint: Array=entry.get("tint",[1,1,1]);var clip: Dictionary=effect.catalog.masters[entry.master].get("cut_clip",{})
        instance_data.append_array(PackedFloat32Array([i*8,0,clip.get("sense",0),clip.get("plane_m",0),tint[0],tint[1],tint[2],entry.get("roughness_delta",0)]))
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
func agent_snapshot() -> Dictionary:return {"state":state.duplicate(),"revision":revision,"metrics":metrics.duplicate(),"gpu_ready":effect.gpu_ready,"failure":effect.failure,"collections":effect.catalog.get("collections",{}),"controls":{"modes":mode_options(),"precompiled_seeds":[2102,7319],"styles":["varied","uniform","legacy"],"face":[0,3],"angles":[-180,180],"zoom":[.35,2.],"focus_m":[-10,10],"roof":"boolean"}}
func _process(_delta: float) -> void:
    if effect.gpu_ready and texture==null:texture=Texture2DRD.new();texture.texture_rd_rid=effect.output_rid;picture.texture=texture
func _exit_tree() -> void:
    if texture!=null:texture.texture_rd_rid=RID()
    if effect!=null:effect.shutdown()
