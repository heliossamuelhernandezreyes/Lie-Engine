extends SceneTree
const Lab=preload("res://lie25_anatomy_lab.gd")
var lab: Node3D
var checks: int=0
var failed: bool=false
var report: Dictionary={"cases":[]}

func check(value: bool,message: String) -> void:
    checks+=1
    if not value:failed=true;push_error(message)

func frames(count: int) -> void:
    for _i in range(count):await process_frame
    await RenderingServer.frame_post_draw

func read_gpu(full: bool=false) -> Dictionary:
    lab.effect.call("request_readback",full)
    for _i in range(180):
        await process_frame
        var data: Dictionary=lab.effect.call("readback")
        if not data.is_empty():return data
    check(false,"Anatomy GPU readback timeout");return {}

func image(name: String,data: Dictionary) -> void:
    var pixels:=PackedByteArray();var values: PackedFloat32Array=data["color"];pixels.resize(values.size())
    for i in range(values.size()):pixels[i]=clampi(roundi(values[i]*255),0,255)
    Image.create_from_data(512,512,false,Image.FORMAT_RGBA8,pixels).save_png("res://lie25-"+name+".png")

func change(values: Dictionary) -> void:
    check(lab.command({"op":"set_values","values":values})["ok"],"Atomic anatomical controls")
    await frames(4)

func mesh_count(node: Node) -> int:
    var count: int=1 if node is MeshInstance3D else 0
    for child in node.get_children():count+=mesh_count(child)
    return count

func _initialize() -> void:call_deferred("run")

func run() -> void:
    lab=Lab.new();root.add_child(lab);await frames(12)
    check(lab.effect.get("capture_loaded"),"Actual anatomical captures loaded: "+str(lab.effect.get("failure")))
    check(lab.effect.get("gpu_ready"),"Anatomical Vulkan pipeline ready: "+str(lab.effect.get("failure")))
    check(mesh_count(lab)==0,"No source geometry drawn")
    if failed:quit(1);return
    var baseline: Dictionary=await read_gpu();image("skin",baseline)
    var original: PackedFloat32Array=baseline["color"].duplicate()
    var idle: int=lab.effect.get("frame_count");await frames(5)
    check(lab.effect.get("frame_count")==idle,"Still anatomical image stays GPU resident")
    for mask in [15,14,12,8]:
        await change({"mask":mask,"unlit":true})
        var data: Dictionary=await read_gpu();image("unlit-mask%d"%mask,data)
        var samples: PackedFloat32Array=FileAccess.get_file_as_bytes("res://captures/anatomy25/samples.bin").to_float32_array()
        var owners: PackedInt32Array=data["winners"];var invalid: int=0;var covered: int=0
        for owner in owners:
            if owner<0:continue
            covered+=1
            if (mask&(1<<int(samples[owner*20+15])))==0:invalid+=1
        check(invalid==0 and covered>1000,"Hidden anatomical layers cannot own output")
        var file:=FileAccess.open("res://lie25-mask%d-depth.bin"%mask,FileAccess.WRITE);file.store_buffer(data["depth"].to_byte_array());file.close()
        report["cases"].append({"mask":mask,"covered_internal_pixels":covered,"invalid_layer_owners":invalid})
        await change({"unlit":false});image("mask%d"%mask,await read_gpu())
    await change({"mask":15});var restored: Dictionary=await read_gpu()
    check(restored["color"]==original,"Restoring layers restores identical image")
    var revision: int=lab.revision
    check(not lab.command({"op":"set_values","values":{"mask":2.5,"light_power":0}})["ok"] and lab.revision==revision and lab.state["light_power"]==4,"Invalid mask does not partially change light")
    check(not lab.command({"op":"set_values","values":{"palette":[[0,0,0],[1,1,1],[1,1,1],[2,0,0]]}})["ok"] and lab.revision==revision,"Out of range tissue color rejected")
    var palette: Array=lab.state["palette"].duplicate(true);palette[0]=[.16,.32,.55]
    await change({"palette":palette});var tinted: Dictionary=await read_gpu();image("recolored",tinted)
    check(tinted["color"]!=original and tinted["asset_uploads"]==1,"Tissue pigment changes without recapturing or reuploading asset")
    await change({"light_color":[.4,.65,1.0],"light_azimuth":65});var relit: Dictionary=await read_gpu();image("relit",relit)
    check(relit["color"]!=tinted["color"] and relit["asset_uploads"]==1,"Light direction and color change actual captures")
    await change({"object_yaw":27});var turned: Dictionary=await read_gpu(true);image("turned",turned)
    var source: PackedFloat32Array=FileAccess.get_file_as_bytes("res://captures/anatomy25/samples.bin").to_float32_array()
    var projected: PackedFloat32Array=turned["projected"];var error: float=0
    var basis:=Basis(Vector3.UP,deg_to_rad(27))
    for i in range(0,int(lab.effect.get("master")["sample_count"]),1009):
        var expected: Vector3=basis*Vector3(source[i*20],source[i*20+1],source[i*20+2])
        error=maxf(error,expected.distance_to(Vector3(projected[i*24],projected[i*24+1],projected[i*24+2])))
    check(error<.00002,"Rigid anatomical samples retain native coordinates under rotation")
    await change({"mask":0});var empty: Dictionary=await read_gpu()
    check(empty["winners"].count(-1)==empty["winners"].size(),"All hidden layers clear output")
    await change({"mask":14,"object_yaw":0,"palette":[[.52,.29,.18],[.32,.045,.028],[.72,.64,.47],[.29,.12,.15]],"light_color":[1,.88,.76],"light_azimuth":-35})
    await frames(2);root.get_texture().get_image().save_png("res://lie25-workshop.png")
    report.merge({"checks":checks,"failed":failed,"rotation_error_m":error,"allocation_bytes":turned["allocation_bytes"],"asset_uploads":turned["asset_uploads"],"device":turned["device"],"master":lab.effect.get("master"),"visible_source_meshes":mesh_count(lab),"limits":["rigid bust only","no facial/body rig","no game cuts","software Vulkan does not prove Android FPS"]})
    var file:=FileAccess.open("res://lie25-diagnostic.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
    print("LIE25 ","FAIL" if failed else "PASS"," ",checks," checks")
    lab.queue_free();await frames(2);quit(1 if failed else 0)
