extends SceneTree
var checks: int=0
var failed: bool=false
var rows: Dictionary={}
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("SCANNED FAIL ",label)
func settle(n: int=8) -> void:
    for i in range(n):await process_frame
func capture(lab: Node) -> Dictionary:
    await settle();lab.effect.request_readback()
    for i in range(180):
        await process_frame
        var value: Dictionary=lab.effect.readback()
        if not value.is_empty():return value
    check(false,"readback");return {}
func save(data: Dictionary,name: String) -> void:
    var file:=FileAccess.open("res://"+name+".rgba32f",FileAccess.WRITE);file.store_buffer(data.color.to_byte_array());file.close()
    var image:=Image.create_from_data(data.output_size,data.output_size,false,Image.FORMAT_RGBAF,data.color.to_byte_array());image.convert(Image.FORMAT_RGBA8);image.save_png("res://"+name+".png")
func difference(a: PackedFloat32Array,b: PackedFloat32Array) -> float:
    if a.size()!=b.size():return INF
    var peak: float=0
    for i in range(a.size()):peak=maxf(peak,absf(a[i]-b[i]))
    return peak
func run() -> void:
    var lab=load("res://lie_scanned_masonry_lab.tscn").instantiate();root.add_child(lab);await settle(20)
    check(lab.metrics.get("configured",false) and lab.effect.gpu_ready,"captured GPU initialize: "+str(lab.effect.failure))
    if not lab.effect.gpu_ready:lab.queue_free();await settle();quit(1);return
    for mode in ["brick","wall","house"]:
        check(lab.command({"op":"set_values","values":{"mode":mode,"seed":2102,"roof":true}}).ok,"mode command")
        var a: Dictionary=await capture(lab)
        if a.is_empty():break
        save(a,mode+"-2102");var coverage: int=0;var finite: bool=true
        for i in range(0,a.color.size(),4):
            if a.color[i+3]>.01:coverage+=1
            for c in range(4):finite=finite and is_finite(a.color[i+c])
        check(finite and coverage>1000,"finite visible real captures")
        check(a.asset_uploads==1 and a.sample_bank_bindings==1,"one bank upload across assemblies")
        check(lab.metrics.original_mesh_draws==0 and a.instances==lab.metrics.instances,"captured instances only")
        var frame: int=lab.effect.frame_count;await settle();check(lab.effect.frame_count==frame,"idle reuse")
        check(lab.command({"op":"set_values","values":{"seed":7319}}).ok,"second seed")
        var b: Dictionary=await capture(lab);save(b,mode+"-7319")
        check(mode=="brick" or difference(a.color,b.color)>.00001,"seed affects assembly")
        check(lab.command({"op":"set_values","values":{"seed":2102}}).ok,"restore seed")
        var restored: Dictionary=await capture(lab);check(difference(a.color,restored.color)<1e-6,"deterministic seed restoration")
        check(lab.command({"op":"set_values","values":{"light":45.0}}).ok,"change light")
        var relit: Dictionary=await capture(lab);check(difference(a.color,relit.color)>.001,"runtime lighting responds")
        lab.command({"op":"set_values","values":{"light":-35.0}})
        rows[mode]={"device":a.device,"instances":a.instances,"sample_invocations":a.sample_invocations,"shared_bank_bytes":a.library_bytes,"exclusive_allocation_bytes":a.exclusive_allocation_bytes,"coverage_pixels":coverage,"source_mesh_draws":0}
        if mode=="wall":
            lab.command({"op":"set_values","values":{"yaw":0.0,"elevation":0.0}});var front: Dictionary=await capture(lab);save(front,"wall-opening-front")
            var hole: Dictionary=lab.recipe.openings[0];var size: Array=lab.recipe.brick_bounds_m;var px: float=float(size[0])+lab.recipe.joint_m;var py: float=float(size[1])+lab.recipe.joint_m
            var center:=Vector3((hole.column+hole.columns*.5)*px-float(lab.recipe.bounds_m[0])*.5-lab.recipe.joint_m*.5,(hole.row+hole.rows*.5)*py-lab.recipe.joint_m*.5,0)
            var pixel: Vector2=lab.camera.unproject_position(center)*float(front.output_size)/Vector2(root.size).x
            # Camera viewport is 1080x740, captured lens is square: derive its
            # coordinates directly from the same calibrated projection.
            var delta: Vector3=center-lab.camera.position;var depth: float=delta.dot(-lab.camera.basis.z);var tangent: float=tan(deg_to_rad(lab.camera.fov)*.5)
            pixel=Vector2((delta.dot(lab.camera.basis.x)/(depth*tangent)+1)*.5,(1-delta.dot(lab.camera.basis.y)/(depth*tangent))*.5)*front.output_size
            var index: int=(int(pixel.y)*front.output_size+int(pixel.x))*4
            check(front.color[index+3]<.01,"real opening stays transparent in native depth/coverage")
            lab.command({"op":"set_values","values":{"yaw":30.0,"elevation":24.0}})
        if mode=="house":
            lab.command({"op":"set_values","values":{"roof":false,"yaw":25.0,"elevation":42.0}});var interior: Dictionary=await capture(lab);save(interior,"house-open-roof")
    if lab.effect.catalog.has("assembly_version"):await construction_checks(lab)
    var revision: int=lab.revision
    check(not lab.command({"op":"set_values","expected_revision":revision-1,"values":{"seed":2102}}).ok,"stale revision")
    check(not lab.command({"op":"set_values","values":{"seed":true}}).ok,"bool seed rejected")
    check(not lab.command({"op":"set_values","values":{"yaw":NAN}}).ok,"nonfinite angle rejected")
    check(lab.revision==revision,"invalid commands atomic")
    # Second consumer must borrow the same actual RD source bank.
    var second=load("res://lie_scanned_masonry_effect.gd").new(720)
    var pending: Dictionary=lab.effect._pending.duplicate(true)
    check(second.configure(pending.parameters,pending.instances,pending.jobs,pending.work),"second consumer configure")
    lab.world_environment.compositor.compositor_effects=[lab.effect,second];await settle(20);second.request_readback();await settle(12)
    var shared: Dictionary=second.readback();check(not shared.is_empty() and shared.get("asset_uploads",-1)==0,"second consumer reuses GPU bank")
    lab.world_environment.compositor.compositor_effects=[lab.effect];second.shutdown();await settle(12);second=null
    lab.effect.request_readback();await settle();check(not lab.effect.readback().is_empty(),"remaining consumer survives release")
    root.get_texture().get_image().save_png("res://scanned-masonry-window.png")
    var report:=FileAccess.open("res://scanned-masonry-native.json",FileAccess.WRITE);report.store_string(JSON.stringify({"checks":checks,"failed":failed,"cases":rows,"physical_android_tested":false,"shared_irradiance_integrated":false},"  "));report.close()
    lab.queue_free();await settle(16);print("SCANNED MASONRY ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
func construction_checks(lab: Node) -> void:
    for mode in ["wall","house"]:
        var images: Dictionary={}
        for style in ["legacy","uniform","varied"]:
            check(lab.command({"op":"set_values","values":{"mode":mode,"style":style,"seed":2102,"yaw":30.0,"elevation":24.0,"roof":true}}).ok,"construction style command")
            var data: Dictionary=await capture(lab);save(data,mode+"-"+style);images[style]=data.color
            check(data.asset_uploads==1,"styles reuse one immutable source bank")
            if style=="varied":
                var orientations: Dictionary={};var tones: Dictionary={};var half_count: int=0
                for entry in lab.recipe.instances:
                    if entry.master in ["scanned_brick","half_left","half_right"]:
                        orientations[entry.orientation]=true;tones[str(entry.tint)]=true
                        if entry.master!="scanned_brick":half_count+=1
                check(orientations.size()==4 and tones.size()>20,"four real rotations and authored per-piece tone")
                check(half_count>0,"actual saw-cut boundary masters")
                var packet: PackedFloat32Array=lab.effect._pending.instances.to_float32_array();var tinted: bool=false
                for i in range(0,packet.size(),24):tinted=tinted or abs(packet[i+20]-1)>.001
                check(tinted,"authored tint reaches actual GPU instance packet")
        check(difference(images.legacy,images.varied)>.01,"construction visibly changes native reconstruction")
        check(difference(images.uniform,images.varied)>.01,"material/orientation variation visibly changes output")
        lab.command({"op":"set_values","values":{"style":"uniform"}});await capture(lab);lab.command({"op":"set_values","values":{"style":"varied"}})
        var restored: Dictionary=await capture(lab);check(difference(images.varied,restored.color)<1e-6,"style restoration deterministic")
    var first:=PackedFloat32Array()
    for face in range(4):
        check(lab.command({"op":"set_values","values":{"mode":"brick","face":face}}).ok,"source-face command")
        var data: Dictionary=await capture(lab);save(data,"brick-face-"+str(face))
        if face==0:first=data.color
        else:check(difference(first,data.color)>.01,"original source faces differ without deformation")
    var revision: int=lab.revision
    check(not lab.command({"op":"set_values","values":{"face":true}}).ok and lab.revision==revision,"bool orientation rejected atomically")
    lab.command({"op":"set_values","values":{"mode":"house","face":0}})
