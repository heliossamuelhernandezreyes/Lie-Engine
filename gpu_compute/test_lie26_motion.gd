extends SceneTree
const Lab=preload("res://lie26_motion_lab.gd")
const Rig=preload("res://lie26_rig.gd")
var lab: Node3D
var checks: int=0
var failed: bool=false
var report: Dictionary={"cases":[]}
var source:=PackedFloat32Array()

func check(value: bool,message: String) -> void:
    checks+=1
    if not value:failed=true;push_error(message)

func frames(count: int) -> void:
    for _i in range(count):await process_frame
    await RenderingServer.frame_post_draw

func read_gpu(full: bool=false) -> Dictionary:
    lab.effect.call("request_readback",full)
    for _i in range(240):
        await process_frame
        var data: Dictionary=lab.effect.call("readback")
        if not data.is_empty():return data
    check(false,"Motion GPU readback timeout");return {}

func image(name: String,data: Dictionary) -> void:
    var pixels:=PackedByteArray();var values: PackedFloat32Array=data["color"];pixels.resize(values.size())
    for i in range(values.size()):pixels[i]=clampi(roundi(values[i]*255),0,255)
    Image.create_from_data(512,512,false,Image.FORMAT_RGBA8,pixels).save_png("res://lie26-"+name+".png")

func change(values: Dictionary) -> void:
    check(lab.command({"op":"set_values","values":values})["ok"],"Atomic motion controls")
    await frames(4)

func mesh_count(node: Node) -> int:
    var count: int=1 if node is MeshInstance3D else 0
    for child in node.get_children():count+=mesh_count(child)
    return count

func _initialize() -> void:call_deferred("run")

func run() -> void:
    lab=Lab.new();root.add_child(lab);await frames(12)
    check(lab.effect.get("capture_loaded"),"Anatomical movement captures loaded: "+str(lab.effect.get("failure")))
    check(lab.effect.get("gpu_ready"),"Anatomical movement Vulkan ready: "+str(lab.effect.get("failure")))
    check(mesh_count(lab)==0,"No source geometry drawn")
    if failed:quit(1);return
    source=FileAccess.get_file_as_bytes("res://captures/anatomy26/samples.bin").to_float32_array()
    var baseline: Dictionary=await read_gpu();var original: PackedFloat32Array=baseline["color"].duplicate();image("rest-lit",baseline)
    var idle: int=lab.effect.get("frame_count");await frames(4)
    check(lab.effect.get("frame_count")==idle,"Stopped pose remains GPU resident")
    var errors: Array=[]
    for case in lab.effect.get("master")["cases"]:
        await change({"pose":case["pose"],"mask":case["mask"],"camera_yaw":case["camera_yaw"],"targets":{},"mode":"manual","unlit":true})
        var data: Dictionary=await read_gpu(true);image(case["name"]+"-unlit",data)
        var owners: PackedInt32Array=data["winners"];var invalid: int=0;var covered: int=0
        for owner in owners:
            if owner<0:continue
            covered+=1
            if (int(case["mask"])&(1<<int(source[owner*20+15])))==0:invalid+=1
        check(covered>2000 and invalid==0,"Posed layer mask retains only enabled tissues")
        var projected: PackedFloat32Array=data["projected"];var error: float=0;var finite: bool=true
        for i in range(0,source.size()/20,997):
            if (int(case["mask"])&(1<<int(source[i*20+15])))==0:continue
            var expected: Vector3=Rig.sample_position(source,i*20,lab.evaluated["skins"])
            var actual:=Vector3(projected[i*24],projected[i*24+1],projected[i*24+2]);finite=finite and actual.is_finite()
            error=maxf(error,expected.distance_to(actual))
            for k in range(24):finite=finite and is_finite(projected[i*24+k])
        check(finite and error<.00002,"GPU joints agree with independent CPU DQ")
        var rigid_error: float=0
        for i in range(int(lab.effect.get("master")["layers"][2]["sample_offset"]),int(lab.effect.get("master")["layers"][2]["sample_offset"]+lab.effect.get("master")["layers"][2]["sample_count"]),1543):
            var p:=Vector3(source[i*20],source[i*20+1],source[i*20+2]);var bid: int=int(source[i*20+3]);var t: Transform3D=lab.evaluated["skins"][bid]
            rigid_error=maxf(rigid_error,(t*p).distance_to(Rig.sample_position(source,i*20,lab.evaluated["skins"])))
        check(rigid_error<.000002,"Anatomical bones remain rigid")
        errors.append(error);report["cases"].append({"name":case["name"],"position_error_m":error,"rigid_bone_error_m":rigid_error,"invalid_layer_owners":invalid,"covered_pixels":covered})
        data.clear();projected=PackedFloat32Array()
        await change({"unlit":false});image(case["name"]+"-lit",await read_gpu())
    var revision: int=lab.revision
    check(not lab.command({"op":"set_values","values":{"light_power":0,"pose":{"right_elbow":145}}})["ok"] and lab.revision==revision and lab.state["light_power"]==35,"Invalid hinge rejects whole transaction")
    check(not lab.command({"op":"set_pose","values":{"right_elbow":NAN}})["ok"],"Nonfinite joint rejected")
    check(not lab.command({"op":"set_values","values":{"targets":{"right_hand":{"position":[0,NAN,0],"pole":[0,1,0]}}}})["ok"],"Nonfinite IK rejected")
    check(not lab.command({"op":"set_pose","values":{"right_elbow":20},"expected_revision":revision-1})["ok"],"Stale pose transaction rejected")
    await change({"pose":{},"mask":15,"camera_yaw":0,"targets":{},"unlit":false})
    var restored: Dictionary=await read_gpu();check(restored["color"]==original,"Rest pose returns identical image")
    await change({"targets":{"right_hand":{"position":[-.25,1.2,.36],"pole":[-.5,.8,.5]}}})
    check(lab.evaluated["ik"]["right_hand"]["residual_m"]<.00002,"Visible hand reaches IK target")
    image("ik-hand",await read_gpu())
    var ik: Dictionary=lab.evaluated["ik"].duplicate(true)
    # Skeleton3D and hidden collision capsules consume the same evaluated rig.
    lab.skeleton.force_update_all_bone_transforms()
    for i in range(15):
        var native: Transform3D=lab.skeleton.get_bone_global_pose(i)
        check(native.origin.distance_to(lab.evaluated["origins"][i])<.00001,"Skeleton and captures share joint pivots")
        var bones: Array=lab.effect.get("master")["bones"];var midpoint: Vector3=(Rig.vector(bones[i]["pivot"])+Rig.vector(bones[i]["end"]))* .5
        check(lab.bodies[i].position.distance_to(lab.evaluated["skins"][i]*midpoint)<.00001,"Invisible collision proxy follows joint")
    await change({"mode":"walk","targets":{},"time":.125})
    var walk1: Dictionary=await read_gpu();image("walk",walk1)
    check(lab.evaluated["ik"]["right_foot"]["residual_m"]<.00003 and lab.evaluated["ik"]["left_foot"]["residual_m"]<.00003,"Walk uses grounded foot IK")
    await change({"time":.625});var walk2: Dictionary=await read_gpu()
    check(walk1["color"]!=walk2["color"] and walk2["asset_uploads"]==1,"Movement changes image with one static asset upload")
    var invalid_packet: PackedByteArray=Rig.packet(lab.evaluated);invalid_packet.encode_float(0,NAN)
    check(not lab.effect.call("configure",lab.effect.get("_parameters"),invalid_packet),"Malformed GPU pose packet rejected")
    await change({"mode":"manual","mask":0});var empty: Dictionary=await read_gpu()
    check(empty["winners"].count(-1)==empty["winners"].size(),"Empty mask clears posed output")
    await change({"mode":"walk","time":.125,"mask":14})
    image("walk-muscles",await read_gpu());await frames(2);root.get_texture().get_image().save_png("res://lie26-workshop.png")
    # Deterministic real GPU frames for the delivered motion clip.
    DirAccess.make_dir_recursive_absolute("res://lie26-frames")
    for i in range(24):
        await change({"mode":"walk","time":i/24.0,"mask":15,"camera_yaw":25})
        var data: Dictionary=await read_gpu();var pixels:=PackedByteArray();var values: PackedFloat32Array=data["color"];pixels.resize(values.size())
        for j in range(values.size()):pixels[j]=clampi(roundi(values[j]*255),0,255)
        Image.create_from_data(512,512,false,Image.FORMAT_RGBA8,pixels).save_png("res://lie26-frames/frame-%03d.png"%i)
    report.merge({"checks":checks,"failed":failed,"allocation_bytes":walk2["allocation_bytes"],"asset_uploads":walk2["asset_uploads"],"device":walk2["device"],"ik":ik,"bone_count":15,"sample_count":lab.effect.get("master")["sample_count"],"visible_source_meshes":mesh_count(lab),"limits":["authored game rig, not physiological motion","individual fingers/cloth/ragdoll pending","no cuts","software Vulkan does not establish physical GPU FPS"]})
    var file:=FileAccess.open("res://lie26-diagnostic.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
    print("LIE26 MOTION ","FAIL" if failed else "PASS"," ",checks," checks")
    lab.queue_free();await frames(2);quit(1 if failed else 0)
