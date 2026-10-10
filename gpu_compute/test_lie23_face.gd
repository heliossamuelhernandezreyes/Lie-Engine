extends SceneTree
const Lab=preload("res://lie23_face_lab.gd")
var lab: Node3D
var checks: int=0
var failed: bool=false
var report: Dictionary={"native_cases":[]}
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;push_error("LIE23 GPU FAIL: "+label)
func _initialize() -> void:call_deferred("run")
func frames(n: int=4) -> void:
    for i in range(n):await process_frame
    await RenderingServer.frame_post_draw
func read_gpu(full: bool=false) -> Dictionary:
    lab.effect.call("request_readback",full)
    for i in range(180):
        await process_frame
        var r: Dictionary=lab.effect.call("readback")
        if not r.is_empty():return r
    check(false,"GPU readback timeout");return {}
func command(values: Dictionary) -> void:check(lab.command({"op":"set_values","values":values})["ok"],"Shared face command")
func image(data: Dictionary,name: String) -> void:
    var img:=Image.create_from_data(data["output_size"],data["output_size"],false,Image.FORMAT_RGBAF,data["color"].to_byte_array());img.convert(Image.FORMAT_RGBA8);img.save_png("res://lie23-"+name+".png")
func screenshot(name: String) -> void:root.get_texture().get_image().save_png("res://lie23-"+name+"-workshop.png")
func meshes(node: Node) -> int:
    var n: int=1 if node is MeshInstance3D else 0
    for c in node.get_children():n+=meshes(c)
    return n
func button(node: Node,text: String) -> Button:
    if node is Button and node.text==text:return node
    for c in node.get_children():
        var b: Button=button(c,text)
        if b!=null:return b
    return null
func fit(node: Node) -> bool:
    if node is PanelContainer:
        var r: Rect2=node.get_global_rect()
        if r.position.x<0 or r.position.y<0 or r.end.x>1280 or r.end.y>800:return false
    for c in node.get_children():
        if not fit(c):return false
    return true
func visible_eyes(data: Dictionary,region: int=0) -> Array:
    var m: Dictionary=lab.effect.get("master");var face: int=m["face_sample_count"];var eye: int=m["eye_sample_count"]
    var count: Array=[0,0];var source: PackedFloat32Array=lab.effect.get("_input")[2].to_float32_array()
    for owner in data["winners"]:
        if owner<face:continue
        var side: int=(owner-face)/eye;var sid: int=face+(owner-face)%eye
        if region==0 or int(source[sid*20+15])==region:count[side]+=1
    return count
func iris_mean(data: Dictionary) -> Vector3:
    var m: Dictionary=lab.effect.get("master");var face: int=m["face_sample_count"];var eye: int=m["eye_sample_count"]
    var source: PackedFloat32Array=lab.effect.get("_input")[2].to_float32_array();var total:=Vector3.ZERO;var count: int=0
    var winners: PackedInt32Array=data["winners"];var pixels: PackedFloat32Array=data["color"];var size: int=data["internal_size"];var scale: int=size/data["output_size"]
    for i in range(winners.size()):
        var owner: int=winners[i]
        if owner<face:continue
        if int(source[(face+(owner-face)%eye)*20+15])!=2:continue
        var p: int=((i/size)/scale*data["output_size"]+(i%size)/scale)*4
        total+=Vector3(pixels[p],pixels[p+1],pixels[p+2]);count+=1
    return total/maxi(count,1)
func difference(a: Dictionary,b: Dictionary) -> float:
    var sum: float=0
    for i in range(a["color"].size()):sum+=absf(a["color"][i]-b["color"][i])
    return sum
func run() -> void:
    lab=Lab.new();root.add_child(lab);command({"camera_yaw":0});await frames(12)
    check(lab.effect.get("capture_loaded") and lab.effect.get("gpu_ready"),"Actual Vulkan open-face captures loaded")
    if failed:quit(1);return
    check(meshes(lab)==0,"Original surfaces stay invisible")
    check(fit(lab.ui),"Controls fit actual window")
    var m: Dictionary=lab.effect.get("master");var source_bytes: int=0
    for metadata in m["buffers"].values():source_bytes+=int(metadata["bytes"])
    check(m["sample_count"]==m["face_sample_count"]+m["eye_sample_count"] and m["invocation_count"]==m["face_sample_count"]+2*m["eye_sample_count"],"One eye library supplies both attachments")
    var oracle: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://captures/face23/native-oracle.json"));var max_skin: float=0;var max_eye: float=0
    for case in oracle["cases"]:
        command({"head_yaw":case["head_yaw"],"blink":case["blink"],"gaze_yaw":case["gaze_yaw"],"gaze_pitch":case["gaze_pitch"],"pupil_radius":case["pupil_radius"]});await frames()
        var data: Dictionary=await read_gpu(true);var projected: PackedFloat32Array=data["projected"];var skin_error: float=0;var eye_error: float=0
        for i in range(oracle["skin_probe_indices"].size()):
            var offset: int=int(oracle["skin_probe_indices"][i])*24;var p: Array=case["skin_positions"][i]
            skin_error=maxf(skin_error,Vector3(projected[offset],projected[offset+1],projected[offset+2]).distance_to(Vector3(p[0],p[1],p[2])))
        for side in range(2):
            for i in range(oracle["eye_probes"].size()):
                var index: int=m["face_sample_count"]+side*m["eye_sample_count"]+int(oracle["eye_probes"][i]["sample"]);var p: Array=case["eye_positions"][side][i];var offset: int=index*24
                eye_error=maxf(eye_error,Vector3(projected[offset],projected[offset+1],projected[offset+2]).distance_to(Vector3(p[0],p[1],p[2])))
        max_skin=maxf(max_skin,skin_error);max_eye=maxf(max_eye,eye_error)
        check(skin_error<.00002,"Native Blender eyelid/head deformation")
        check(eye_error<.00002,"Native Blender eye attachment, gaze and pupil")
        report["native_cases"].append({"head_yaw":case["head_yaw"],"blink":case["blink"],"skin_error_m":skin_error,"eye_error_m":eye_error})
    command({"head_yaw":0,"blink":0,"gaze_yaw":0,"gaze_pitch":0,"pupil_radius":.0017});await frames();var open: Dictionary=await read_gpu();image(open,"open");screenshot("open")
    var counts: Array=visible_eyes(open);check(counts[0]>100 and counts[1]>100,"Both eyes are visible inside actual openings")
    var blue: Vector3=iris_mean(open);check(blue.z>blue.x*1.2,"Blue iris appears in integrated face")
    command({"blink":.5});await frames();var half: Dictionary=await read_gpu();image(half,"half-blink")
    var hc: Array=visible_eyes(half);check(hc[0]+hc[1]<counts[0]+counts[1],"Partial blink reduces eye visibility continuously")
    command({"blink":1});await frames();var closed: Dictionary=await read_gpu();image(closed,"closed");screenshot("closed")
    var cc: Array=visible_eyes(closed);check(cc[0]+cc[1]<maxi(3,int((counts[0]+counts[1])*.02)),"Closed lids occlude eyes through shared depth")
    check(difference(closed,open)>10,"Blink changes captured geometry and shading")
    # Hidden eyes must not tint the closed lids through weighted material mixing.
    command({"iris_color":[1,0,0]});await frames();var hidden: Dictionary=await read_gpu()
    check(difference(hidden,closed)<.2,"Hidden iris cannot leak color through closed lids")
    command({"blink":0,"iris_color":[.22,.57,.76]});await frames()
    var brown: Button=button(lab.ui,"Marrón");check(brown!=null,"Actual user iris preset")
    brown.pressed.emit();await frames();var brown_image: Dictionary=await read_gpu();image(brown_image,"brown")
    var bm: Vector3=iris_mean(brown_image);check(bm.x>bm.z*1.2,"User changes iris without recapture")
    command({"iris_color":[.37,.62,.28],"pupil_radius":.0008});await frames();var small: Dictionary=await read_gpu();image(small,"small-pupil")
    command({"pupil_radius":.0032});await frames();var large: Dictionary=await read_gpu();image(large,"large-pupil")
    var sc: Array=visible_eyes(small,3);var lc: Array=visible_eyes(large,3);check(lc[0]+lc[1]>maxi((sc[0]+sc[1])*3,50),"Integrated pupil changes actual geometry")
    var dark: Button=button(lab.ui,"Oscura");dark.pressed.emit();await frames();var dark_image: Dictionary=await read_gpu();image(dark_image,"skin-dark");screenshot("skin-dark")
    check(difference(dark_image,large)>20 and visible_eyes(dark_image)==visible_eyes(large),"Skin tint changes material, not eye geometry")
    command({"skin_tint":[1,1,1],"iris_color":[.22,.57,.76],"pupil_radius":.0017,"gaze_yaw":25,"gaze_pitch":-12});await frames();var gaze: Dictionary=await read_gpu();image(gaze,"gaze");screenshot("gaze")
    check(difference(gaze,open)>10,"Invisible eye rotation changes view")
    command({"gaze_yaw":0,"gaze_pitch":0});await frames();var before: int=lab.effect.get("frame_count");await frames(8)
    check(lab.effect.get("frame_count")==before,"Still portrait reuses GPU image")
    var snapshot: Dictionary=lab.document.snapshot();check(not lab.command({"op":"set_values","values":{"head_yaw":10,"skin_tint":[NAN,1,1]}})["ok"] and lab.document.snapshot()==snapshot,"Live invalid material edit is atomic")
    var packet: PackedByteArray=lab.effect.get("_parameters");check(not lab.effect.call("configure",PackedByteArray()),"Renderer rejects incomplete packet")
    var bad: PackedByteArray=packet.duplicate();bad.encode_float(280,1);check(not lab.effect.call("configure",bad),"Renderer rejects inconsistent sample jobs")
    var inbox:=FileAccess.open("user://face23/inbox.json",FileAccess.WRITE);inbox.store_string(JSON.stringify({"request_id":"lie23-face-live","request":{"op":"set_values","expected_revision":lab.document.revision,"values":{"head_yaw":10}}}));inbox.close();lab.call("_poll_agent")
    var response: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://face23/outbox.json"));check(response["request_id"]=="lie23-face-live" and response["result"]["ok"],"Live correlated agent changes integrated face")
    command({"head_yaw":0,"framing":"eyes"});await frames();var close: Dictionary=await read_gpu();image(close,"eyes-close");screenshot("eyes-close")
    var sequence: Array=[]
    for i in range(13):
        var blink: float=sin(float(i)/12*PI)
        command({"blink":blink});await frames(2);var data: Dictionary=await read_gpu();image(data,"blink-%02d"%i);sequence.append({"index":i,"blink":blink,"time_us":Time.get_ticks_usec(),"gpu_frames":data["frames"]})
    command({"blink":0,"framing":"bust","head_yaw":20});await frames();var bust: Dictionary=await read_gpu();image(bust,"bust");screenshot("bust")
    check(fit(lab.ui),"Stats and controls fit after rendering")
    check(lab.command({"op":"set_playing","value":true})["ok"],"User playback enabled");await frames(6)
    check(lab.effect.get("frame_count")>bust["frames"],"Playback updates GPU poses")
    lab.command({"op":"set_playing","value":false});await frames();var final: Dictionary=await read_gpu()
    check(final["asset_uploads"]==1 and meshes(lab)==0,"All changes share immutable captures and hidden surfaces")
    var finite: bool=true
    for v in final["color"]:
        if not is_finite(v):finite=false
    check(finite,"Finite final face image")
    report.merge({"checks":checks,"failed":failed,"device":final["device"],"allocation_bytes":final["allocation_bytes"],"source_bytes":source_bytes,"stored_samples":m["sample_count"],"sample_invocations":m["invocation_count"],"eye_library_copies":1,"asset_uploads":final["asset_uploads"],"open_eye_pixels":counts,"half_eye_pixels":hc,"closed_eye_pixels":cc,"small_pupil_pixels":sc,"large_pupil_pixels":lc,"max_skin_error_m":max_skin,"max_eye_error_m":max_eye,"sequence":sequence,"profile":final["profile"],"output_size":final["output_size"],"internal_size":final["internal_size"],"original_mesh_drawn":false,"android_measured":false})
    var file:=FileAccess.open("res://lie23-diagnostic.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    print("LIE23 GPU ","FAIL" if failed else "PASS"," ",checks," checks ",JSON.stringify(report));lab.queue_free();await frames(3);quit(1 if failed else 0)
