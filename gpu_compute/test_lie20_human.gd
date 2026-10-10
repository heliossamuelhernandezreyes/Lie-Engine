extends SceneTree
const Lab=preload("res://lie20_human_lab.gd")
var lab: Node3D
var failed: bool=false
var checks: int=0
var report: Dictionary={"cases":[],"deformation_cases":[],"limits":[],"visible_source_meshes":0}

func check(value: bool,message: String) -> void:
    checks+=1
    if not value: failed=true;push_error(message)

func frames(count: int) -> void:
    for _i in range(count): await process_frame
    await RenderingServer.frame_post_draw

func read_gpu() -> Dictionary:
    lab.effect.call("request_readback")
    for _i in range(120):
        await process_frame
        var data: Dictionary=lab.effect.call("readback")
        if not data.is_empty(): return data
    check(false,"human GPU readback timeout");return {}

func write_frame(name: String,data: Dictionary) -> void:
    var values: PackedFloat32Array=data["color"];var pixels:=PackedByteArray();pixels.resize(512*512*4)
    for i in range(values.size()): pixels[i]=clampi(roundi(values[i]*255),0,255)
    var image:=Image.create_from_data(512,512,false,Image.FORMAT_RGBA8,pixels)
    image.save_png("res://lie20-"+name+".png")

func source_meshes(node: Node) -> int:
    var total: int=1 if node is MeshInstance3D else 0
    for child in node.get_children(): total+=source_meshes(child)
    return total

func _initialize() -> void: call_deferred("run")

func run() -> void:
    lab=Lab.new();root.add_child(lab)
    await frames(12)
    check(lab.effect.get("capture_loaded"),"Blender human captures loaded")
    check(lab.effect.get("gpu_ready"),"actual human Vulkan pipeline ready")
    check(source_meshes(lab)==0,"original meshes never drawn by Lie")
    if failed: quit(1);return
    var idle_updates: int=lab.effect.get("frame_count");await frames(6)
    check(lab.effect.get("frame_count")==idle_updates,"static portrait reuses its completed GPU image")
    var oracle: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://captures/human_master/deformation-oracle.json"))
    var max_error: float=0
    for case in oracle["cases"]:
        check(lab.command({"op":"set_values","values":{"head_yaw":case["head_yaw"],"lid_squeeze":case["lid_squeeze"],"jaw_drop":case["jaw_drop"]}})["ok"],"authored human pose")
        await frames(4)
        var data: Dictionary=await read_gpu()
        if data.is_empty(): quit(1);return
        var points: PackedFloat32Array=data["projected"];var error: float=0
        for j in range(oracle["probe_indices"].size()):
            var index: int=int(oracle["probe_indices"][j])*16
            var actual:=Vector3(points[index],points[index+1],points[index+2])
            var p: Array=case["probe_positions"][j];var expected:=Vector3(p[0],p[1],p[2])
            error=maxf(error,actual.distance_to(expected))
        max_error=maxf(max_error,error);check(error<.00002,"GPU captured deformation versus native Blender armature")
        report["deformation_cases"].append({"head_yaw":case["head_yaw"],"lid_squeeze":case["lid_squeeze"],"jaw_drop":case["jaw_drop"],"max_position_error_m":error})
        check(data["asset_uploads"]==1,"poses reuse immutable capture buffers")
    var cases: Array=[{"name":"neutral","head_yaw":0,"lid_squeeze":0,"jaw_drop":0,"camera_yaw":12,"camera_elevation":5,"distance":.85},
        {"name":"turned","head_yaw":25,"lid_squeeze":0,"jaw_drop":0,"camera_yaw":12,"camera_elevation":5,"distance":.85},
        {"name":"corrective","head_yaw":15,"lid_squeeze":.7,"jaw_drop":.7,"camera_yaw":12,"camera_elevation":5,"distance":.85},
        {"name":"profile","head_yaw":-15,"lid_squeeze":0,"jaw_drop":0,"camera_yaw":65,"camera_elevation":5,"distance":.85},
        {"name":"close","head_yaw":0,"lid_squeeze":0,"jaw_drop":0,"camera_yaw":12,"camera_elevation":5,"distance":.62}]
    for case in cases:
        var values: Dictionary=case.duplicate();var name: String=values["name"];values.erase("name")
        check(lab.command({"op":"set_values","values":values})["ok"],"human camera/pose controls")
        await frames(5);var data: Dictionary=await read_gpu()
        if data.is_empty(): quit(1);return
        write_frame(name,data)
        var valid: int=0;var nonfinite: int=0
        for index in data["winners"]: if index>=0: valid+=1
        for value in data["color"]: if not is_finite(value): nonfinite+=1
        check(valid>20000 and nonfinite==0,"finite covered human image")
        report["cases"].append({"name":name,"valid_pixels":valid,"frames":data["frames"]})
    lab.command({"op":"set_values","values":{"head_yaw":0,"lid_squeeze":0,"jaw_drop":0,"camera_yaw":12,"distance":.85,"sss":0}})
    await frames(4);var no_sss: Dictionary=await read_gpu();write_frame("sss-off",no_sss)
    lab.command({"op":"set_values","values":{"sss":1}});await frames(4);var with_sss: Dictionary=await read_gpu();write_frame("sss-on",with_sss)
    var difference: float=0
    for i in range(no_sss["color"].size()): difference+=absf(float(no_sss["color"][i])-float(with_sss["color"][i]))
    check(difference>1,"skin scattering changes the actual image")
    lab.command({"op":"set_values","values":{"shadows":false}});await frames(4)
    var no_shadows: Dictionary=await read_gpu();write_frame("shadows-off",no_shadows)
    var shadow_difference: float=0
    for i in range(no_shadows["color"].size()): shadow_difference+=absf(float(no_shadows["color"][i])-float(with_sss["color"][i]))
    check(shadow_difference>1,"sample-based shadows change the actual image")
    lab.command({"op":"set_values","values":{"shadows":true}});await frames(4)
    # Real user slider invokes exactly the same authoring operation.
    var before: int=lab.document.revision;(lab.controls["head_yaw"] as HSlider).value=10
    check(lab.document.state["head_yaw"]==10 and lab.document.revision==before+1,"visible human controls share commands")
    var revision: int=lab.document.revision
    var accepted: Dictionary=lab.command(JSON.parse_string(JSON.stringify({"op":"set_values","expected_revision":revision,"values":{"head_yaw":-8}})))
    check(accepted["ok"],"JSON numeric revision accepted")
    check(not lab.command({"op":"set_values","expected_revision":revision,"values":{"head_yaw":8}})["ok"] and lab.document.state["head_yaw"]==-8,"stale agent cannot overwrite human controls")
    # Correlated live inbox remains compatible with the existing Python client.
    var inbox:=FileAccess.open("user://human/inbox.json",FileAccess.WRITE)
    inbox.store_string(JSON.stringify({"request_id":"lie20-human-live","request":{"op":"set_values","expected_revision":lab.document.revision,"values":{"head_yaw":14}}}));inbox.close()
    lab.call("_poll_agent")
    var response: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://human/outbox.json"))
    check(response["request_id"]=="lie20-human-live" and response["result"]["ok"] and lab.document.state["head_yaw"]==14,"live agent and user share human document")
    for i in range(16):
        lab.command({"op":"set_values","values":{"head_yaw":-20+40*float(i)/15,"jaw_drop":.35*(1-cos(TAU*float(i)/15))}})
        await frames(2);write_frame("motion-%02d" % i,await read_gpu())
    lab.command({"op":"set_values","values":{"head_yaw":10,"jaw_drop":0,"sss":1}});await frames(4)
    var final: Dictionary=await read_gpu()
    root.get_texture().get_image().save_png("res://lie20-workshop.png")
    report.merge({"checks":checks,"failed":failed,"max_position_error_m":max_error,"allocation_bytes":final["allocation_bytes"],"asset_uploads":final["asset_uploads"],
        "profile":final["profile"],"device":final["device"],"sss_image_l1_difference":difference,"shadow_image_l1_difference":shadow_difference,"master":lab.effect.get("master"),"snapshot":lab.agent_snapshot(),
        "timing_scope":"Lie GPU passes only, software Vulkan; not physical GPU, complete frame time or Android performance."},true)
    var file:=FileAccess.open("res://lie20-diagnostic.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    print("LIE20 HUMAN ","FAIL" if failed else "PASS"," ",checks," checks; Blender deformation error ",max_error," m")
    lab.queue_free();await frames(2);quit(1 if failed else 0)
