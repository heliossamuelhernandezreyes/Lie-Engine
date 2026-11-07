extends SceneTree
var checks: int=0
var failed: bool=false
var rows: Dictionary={}
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("HQ CONSTRUCTION FAIL ",label)
func settle(n: int=6) -> void:
    for i in range(n):await process_frame
func capture(lab: Node) -> Dictionary:
    await settle();lab.effect.request_readback()
    for i in range(240):
        await process_frame
        var data: Dictionary=lab.effect.readback()
        if not data.is_empty():return data
    check(false,"readback");return {}
func save(data: Dictionary,name: String) -> void:
    var image:=Image.create_from_data(data.output_size,data.output_size,false,Image.FORMAT_RGBAF,data.color.to_byte_array());image.convert(Image.FORMAT_RGBA8);image.save_png("res://"+name+".png")
func difference(a: PackedFloat32Array,b: PackedFloat32Array) -> float:
    var peak: float=0
    for i in range(a.size()):peak=maxf(peak,absf(a[i]-b[i]))
    return peak
func alpha_at(lab: Node,data: Dictionary,p: Vector3) -> float:
    var d: Vector3=p-lab.camera.position;var z: float=d.dot(-lab.camera.basis.z);var t: float=tan(deg_to_rad(lab.camera.fov)*.5)
    var uv:=Vector2((d.dot(lab.camera.basis.x)/(z*t)+1)*.5,(1-d.dot(lab.camera.basis.y)/(z*t))*.5)
    if uv.x<0 or uv.x>=1 or uv.y<0 or uv.y>=1:return 0
    return data.color[(int(uv.y*data.output_size)*data.output_size+int(uv.x*data.output_size))*4+3]
func run() -> void:
    var lab=load("res://lie_hq_construction_lab.tscn").instantiate();root.add_child(lab);await settle(18)
    check(lab.effect.capture_loaded,"all source contracts load: "+lab.effect.failure)
    if not lab.effect.capture_loaded:lab.queue_free();await settle();quit(1);return
    for mode in ["corner","opening","roof","door"]:
        check(lab.command({"op":"set_values","values":{"mode":mode,"seed":2102,"normals":true,"yaw":32.,"elevation":22.,"light":-35.,"zoom":1.,"lod":-1}}).ok,"module command")
        var a: Dictionary=await capture(lab)
        if a.is_empty():continue
        save(a,mode+"-front");var pixels: int=0;var finite: bool=true
        for i in range(0,a.color.size(),4):
            if a.color[i+3]>.01:pixels+=1
            for c in range(4):finite=finite and is_finite(a.color[i+c])
        check(finite and pixels>1000 and lab.effect.gpu_ready,"finite native captured geometry")
        check(lab.metrics.source_mesh_draws==0 and a.banks==5,"five banks, no source mesh draw")
        lab.command({"op":"set_values","values":{"reverse_banks":true}});var b: Dictionary=await capture(lab)
        check(a.depth==b.depth and a.shadow==b.shadow and difference(a.color,b.color)<1e-6,"bank order leaves depth, shadow and material unchanged")
        lab.command({"op":"set_values","values":{"reverse_banks":false,"light":55.}});var lit: Dictionary=await capture(lab)
        check(difference(a.color,lit.color)>.001,"runtime light response")
        lab.command({"op":"set_values","values":{"light":-35.,"yaw":-145.,"elevation":18.}});var back: Dictionary=await capture(lab);save(back,mode+"-back")
        rows[mode]={"instances":a.instances,"samples":a.sample_invocations,"source_bytes":a.library_bytes,"exclusive_bytes":a.exclusive_allocation_bytes,"device":a.device,"pixels":pixels}
    for angle in [0.,180.]:
        lab.command({"op":"set_values","values":{"mode":"corner","yaw":angle,"elevation":0.,"zoom":1.}});var data: Dictionary=await capture(lab);save(data,"corner-opening-"+str(int(angle)))
        var center: Array=lab.recipe.opening.center;var clear: Array=lab.recipe.opening.clear_size;var empty: bool=true
        for x in range(7):
            for y in range(5):empty=empty and alpha_at(lab,data,Vector3(center[0]+(float(x)/6.-.5)*clear[0]*.75,center[1]+(float(y)/4.-.5)*clear[1]*.75,center[2]))<.01
        check(empty,"opening remains empty on both sides")
    for mode in ["asset_mortar_bed","asset_concrete_lintel","asset_wood_beam"]:
        lab.command({"op":"set_values","values":{"mode":mode,"yaw":25.,"elevation":18.,"normals":true,"shadows":true}});var a: Dictionary=await capture(lab);save(a,mode+"-normal")
        lab.command({"op":"set_values","values":{"normals":false}});var b: Dictionary=await capture(lab);save(b,mode+"-geometry")
        check(a.depth==b.depth and a.shadow==b.shadow,"optical normals never alter depth or caster geometry")
        check(difference(a.color,b.color)>.001,"normal channel changes shading")
    lab.command({"op":"set_values","values":{"mode":"shadow","yaw":15.,"elevation":55.,"normals":true,"shadows":true,"occluder":true}});var shaded: Dictionary=await capture(lab);save(shaded,"shared-shadow")
    lab.command({"op":"set_values","values":{"shadows":false}});var unshadowed: Dictionary=await capture(lab);save(unshadowed,"without-shadow")
    check(shaded.depth==unshadowed.depth and difference(shaded.color,unshadowed.color)>.005,"wood casts into common concrete receiver depth/shadow scene")
    lab.command({"op":"set_values","values":{"mode":"occlusion","yaw":0.,"elevation":0.,"occluder":true,"shadows":true}});var covered: Dictionary=await capture(lab);save(covered,"cross-bank-front")
    lab.command({"op":"set_values","values":{"occluder":false}});var revealed: Dictionary=await capture(lab);save(revealed,"cross-bank-revealed")
    check(covered.depth!=revealed.depth and difference(covered.color,revealed.color)>.01,"front bank geometrically occludes rear bank")
    lab.command({"op":"set_values","values":{"mode":"door","yaw":25.,"elevation":15.,"occluder":true,"door_angle":0.}});var closed: Dictionary=await capture(lab)
    lab.command({"op":"set_values","values":{"door_angle":75.}});var opened: Dictionary=await capture(lab);save(opened,"door-open")
    check(closed.depth!=opened.depth and closed.instances==opened.instances,"rigid hinged door opens without source duplication")
    var uploads: int=opened.asset_uploads;var frame: int=lab.effect.frame_count;await settle();check(lab.effect.frame_count==frame,"idle cache")
    var original: Dictionary=lab.effect._pending.duplicate(true);var invalid: PackedByteArray=original.instances.duplicate();invalid.encode_float(68,INF)
    check(not lab.effect.configure(original.parameters,invalid,original.jobs,original.work),"nonfinite bank address rejected")
    var bad_jobs: PackedByteArray=original.jobs.duplicate();var bank_id: int=int(original.instances.decode_float(68));bad_jobs.encode_s32(0,lab.effect.banks[bank_id].catalog.sample_count)
    check(not lab.effect.configure(original.parameters,original.instances,bad_jobs,original.work),"source ranges validated against their own bank")
    var second=load("res://lie_construction_scene_effect.gd").new(960);var pending: Dictionary=lab.effect._pending.duplicate(true)
    check(second.configure(pending.parameters,pending.instances,pending.jobs,pending.work),"second scene configure")
    lab.world_environment.compositor.compositor_effects=[lab.effect,second];await settle(18);second.request_readback();await settle(12);var shared: Dictionary=second.readback()
    check(not shared.is_empty() and shared.get("asset_uploads",-1)==0,"second scene borrows all geometry and optical banks")
    lab.world_environment.compositor.compositor_effects=[lab.effect];second.shutdown();second=null;await settle(12)
    check(not (await capture(lab)).is_empty() and lab.effect.asset_uploads==uploads,"remaining consumer survives release")
    var revision: int=lab.revision
    for bad in [{"zoom":true},{"normals":1},{"light":NAN},{"mode":"glass"},{"door_angle":150.}]:check(not lab.command({"op":"set_values","values":bad}).ok and lab.revision==revision,"invalid command is atomic")
    var f:=FileAccess.open("res://hq-construction-native.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failed":failed,"cases":rows,"physical_android_tested":false,"shared_indirect_field_integrated":false},"  "));f.close()
    lab.queue_free();await settle(16);print("HQ CONSTRUCTION ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
