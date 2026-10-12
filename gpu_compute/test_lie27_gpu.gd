extends SceneTree
const Lab=preload("res://lie27_regions_lab.gd")
var lab: Node3D
var fixture: Dictionary={}
var eye_reference: Dictionary={}
var coverage: Dictionary={}
var sample_tags:=PackedByteArray()
var checks: int=0
var failed: bool=false
var report: Dictionary={"frames":[],"limits":["software Vulkan; physical GPU/Android performance unmeasured","authored expression fields; no physiological muscle simulation","body reconstruction holes remain under evaluation"]}
func check(ok: bool,message: String) -> void:
    checks+=1
    if not ok:failed=true;push_error(message)
func frames(n: int=3) -> void:
    for i in range(n):await process_frame
func read() -> Dictionary:
    lab.effect.call("request_readback")
    for i in range(100):
        await frames(1)
        var result: Dictionary=lab.effect.call("readback")
        if not result.is_empty():return result
    check(false,"Readback completed");return {}
func save_image(name: String,data: Dictionary) -> void:
    var values: PackedFloat32Array=data["color"];var bytes:=PackedByteArray();bytes.resize(values.size())
    for i in range(values.size()):bytes[i]=clampi(roundi(values[i]*255),0,255)
    Image.create_from_data(512,512,false,Image.FORMAT_RGBA8,bytes).save_png("res://lie27-"+name+".png")
    if not name.begins_with("blink-"):
        var file:=FileAccess.open("res://lie27-"+name+"-owners.bin",FileAccess.WRITE);file.store_buffer(data["winners"].to_byte_array());file.close()
func face(left: float=0,right: float=0,smile: float=0,frown: float=0,brow: float=0,down: float=0,jaw: float=0) -> Dictionary:
    return {"blink_left":left,"blink_right":right,"smile":smile,"frown":frown,"brow_up":brow,"brow_down":down,"jaw_open":jaw}
func change(values: Dictionary) -> void:
    check(lab.command({"op":"set_values","values":values})["ok"],"Valid controls accepted")
    await frames(4)
func verify_probes(name: String,data: Dictionary) -> void:
    var expected: Array=[]
    for case in fixture["cases"]:
        if case["name"]==name:expected=case["positions"]
    var probes: Array=data["probes"];var error: float=0;var finite: bool=true
    check(probes.size()==expected.size(),"Probe count matches independent source reference")
    for i in range(mini(probes.size(),expected.size())):
        var v: PackedFloat32Array=probes[i]
        error=maxf(error,Vector3(v[0],v[1],v[2]).distance_to(Lab.Rig.vector(expected[i])))
        for component in v:finite=finite and is_finite(component)
    check(finite and error<.00002,"Independent GPU deformation "+name)
    report["frames"].append({"case":name,"max_error_m":error,"finite":finite})
func visible_eyes(data: Dictionary) -> Dictionary:
    var owners: PackedInt32Array=data["winners"];var result: Dictionary={}
    for side in ["left","right"]:
        var indices: Dictionary={};var pixels: int=0
        for index in eye_reference[side]:indices[int(index)]=true
        for owner in owners:
            if indices.has(owner):pixels+=1
        result[side]=pixels
    return result
func verify_coverage(name: String,data: Dictionary) -> void:
    var filename: String=""
    for case in coverage["cases"]:
        if case["name"]==name:filename=case["file"]
    check(not filename.is_empty(),"Independent skin reference exists: "+name)
    var reference: PackedByteArray=FileAccess.get_file_as_bytes("res://captures/anatomy27/"+filename)
    var owners: PackedInt32Array=data["winners"];var skin_leaks: int=0;var eye_leaks: int=0;var missing: int=0;var protected: int=0;var leak_layers: Dictionary={}
    for i in range(reference.size()):
        var expected: int=reference[i]
        if expected==0:continue
        protected+=1;var owner: int=owners[i]
        if owner<0:missing+=1;continue
        if expected==1 and sample_tags[owner*2]!=0:
            skin_leaks+=1;var key: String=str(sample_tags[owner*2])+":"+str(sample_tags[owner*2+1]);leak_layers[key]=leak_layers.get(key,0)+1
        if expected==2 and sample_tags[owner*2+1]!=10:eye_leaks+=1
        if expected==3 and sample_tags[owner*2]!=0 and sample_tags[owner*2+1]!=10:skin_leaks+=1
    check(protected>1000 and skin_leaks==0 and eye_leaks==0 and missing==0,"Intact skin/ocular material ownership: "+name)
    if not report.has("skin_coverage"):report["skin_coverage"]=[]
    report["skin_coverage"].append({"case":name,"protected_pixels":protected,"skin_leaks":skin_leaks,"eye_wrong_material":eye_leaks,"missing":missing,"leak_layers":leak_layers})
func same_eye_pixels(a: Dictionary,b: Dictionary) -> bool:
    var wa: PackedInt32Array=a["winners"];var wb: PackedInt32Array=b["winners"];var ca: PackedFloat32Array=a["color"];var cb: PackedFloat32Array=b["color"];var compared: int=0
    for y in range(512):
        for x in range(512):
            var safe: bool=true
            for dy in range(2):
                for dx in range(2):
                    var i: int=(y*2+dy)*1024+x*2+dx
                    safe=safe and wa[i]>=0 and wb[i]>=0 and sample_tags[wa[i]*2+1]==10 and sample_tags[wb[i]*2+1]==10
            if safe:
                compared+=1
                for channel in range(3):
                    if ca[(y*512+x)*4+channel]!=cb[(y*512+x)*4+channel]:return false
    return compared>100
func same_non_eye_pixels(a: Dictionary,b: Dictionary) -> bool:
    var wa: PackedInt32Array=a["winners"];var wb: PackedInt32Array=b["winners"];var ca: PackedFloat32Array=a["color"];var cb: PackedFloat32Array=b["color"];var compared: int=0
    for y in range(512):
        for x in range(512):
            var safe: bool=true
            for dy in range(2):
                for dx in range(2):
                    var i: int=(y*2+dy)*1024+x*2+dx
                    if (wa[i]>=0 and sample_tags[wa[i]*2+1]==10) or (wb[i]>=0 and sample_tags[wb[i]*2+1]==10):safe=false
            if safe:
                compared+=1
                for channel in range(3):
                    if ca[(y*512+x)*4+channel]!=cb[(y*512+x)*4+channel]:return false
    return compared>10000
func _initialize() -> void:call_deferred("run")
func run() -> void:
    lab=Lab.new();root.add_child(lab);await frames(12)
    check(lab.effect.get("capture_loaded"),"Region bank loads: "+str(lab.effect.get("failure")))
    check(lab.effect.get("gpu_ready"),"Region Vulkan ready: "+str(lab.effect.get("failure")))
    if failed:quit(1);return
    fixture=JSON.parse_string(FileAccess.get_file_as_string("res://captures/anatomy27/region-probes.json"))
    eye_reference=JSON.parse_string(FileAccess.get_file_as_string("res://captures/anatomy27/eyeball-sample-indices.json"))
    coverage=JSON.parse_string(FileAccess.get_file_as_string("res://captures/anatomy27/coverage-reference.json"))
    sample_tags=FileAccess.get_file_as_bytes("res://captures/anatomy27/sample-material-reference.bin")
    lab.effect.call("set_probe_indices",PackedInt32Array(fixture["indices"]))
    check(lab.skeleton.get_bone_count()==45 and lab.joint_spheres.size()==44,"Body and phalanges have shared skeleton and spherical proxies")
    await change({"focus":"face","distance":.35,"face":face(),"mask":15,"pose":{}})
    var neutral: Dictionary=await read();save_image("face-neutral",neutral);verify_probes("neutral",neutral);verify_coverage("neutral",neutral)
    var initial: PackedFloat32Array=neutral["color"].duplicate()
    await change({"face":face(1,1)});var closed: Dictionary=await read();save_image("face-closed",closed);verify_probes("closed",closed);verify_coverage("closed",closed)
    check(initial!=closed["color"],"Captured eyelid closure changes visible face")
    await change({"face":face(1,0)});var wink: Dictionary=await read();save_image("face-wink",wink);verify_probes("wink",wink);verify_coverage("wink",wink)
    check(wink["color"]!=closed["color"] and wink["color"]!=initial,"Eyelids operate independently")
    var open_eyes: Dictionary=visible_eyes(neutral);var closed_eyes: Dictionary=visible_eyes(closed);var wink_eyes: Dictionary=visible_eyes(wink)
    check(open_eyes["left"]>20 and open_eyes["right"]>20,"Both native eyes visible when open")
    check(closed_eyes["left"]==0 and closed_eyes["right"]==0,"Connected eyelids fully occlude native eyeballs")
    check(wink_eyes["left"]==0 and wink_eyes["right"]==open_eyes["right"],"Left eyelid occludes only left eye")
    report["eye_visibility_pixels"]={"neutral":open_eyes,"closed":closed_eyes,"wink":wink_eyes}
    await change({"face":face(0,0,1)});var smile: Dictionary=await read();save_image("face-smile",smile);verify_probes("smile",smile);verify_coverage("smile",smile)
    check(smile["color"]!=initial,"Commissure field changes face")
    await change({"face":face(0,0,0,1,0,1)});var frown: Dictionary=await read();save_image("face-frown",frown);verify_probes("frown",frown);verify_coverage("frown",frown)
    await change({"face":face(0,0,0,0,1,0,1)});var surprise: Dictionary=await read();save_image("face-surprise",surprise);verify_probes("surprise",surprise);verify_coverage("surprise",surprise)
    await change({"face":face(),"pose":{"head_yaw":25,"head_pitch":15}});var turned: Dictionary=await read();save_image("head-turn",turned);verify_probes("head_turn",turned);verify_coverage("head_turn",turned)
    await change({"face":face(1,1)});var turned_closed: Dictionary=await read();save_image("head-turn-closed",turned_closed);verify_probes("head_turn_closed",turned_closed);verify_coverage("head_turn_closed",turned_closed)
    var turned_eyes: Dictionary=visible_eyes(turned_closed);report["eye_visibility_pixels"]["head_turn_closed"]=turned_eyes
    check(turned_eyes["left"]==0 and turned_eyes["right"]==0,"Turned closed lids fully occlude both native eyes")
    await change({"face":face(),"pose":{}});var restored: Dictionary=await read()
    check(restored["color"]==initial,"Neutral pose restores identical output")
    var revision: int=lab.revision
    check(not lab.command({"op":"set_values","values":{"light_power":0,"face":face(2,0)}})["ok"] and lab.revision==revision and lab.state["light_power"]==70,"Invalid expression rejects whole transaction")
    check(not lab.command({"op":"set_values","values":{"face":face(NAN,0)}})["ok"],"NaN face rejected")
    check(not lab.command({"op":"set_pose","values":{"right_index":95}})["ok"],"Excess finger curl rejected")
    await change({"focus":"hand","distance":.35,"pose":{}});var hand: Dictionary=await read();save_image("hand-open",hand)
    await change({"pose":{"right_index":65,"right_middle":70,"right_ring":70,"right_little":70,"right_thumb":25}});var fist: Dictionary=await read();save_image("hand-fist",fist);verify_probes("fist",fist)
    check(hand["color"]!=fist["color"],"Phalanges change captured hand")
    for i in range(lab.joint_spheres.size()):
        var zone: Dictionary=lab.effect.get("master")["joint_regions"][i];var center: Vector3=Lab.Rig.vector(zone["center"])
        check(lab.joint_spheres[i].position.distance_to(lab.evaluated["skins"][int(zone["parent"])]*center)<.00001,"Spherical proxy follows evaluated parent")
    await change({"focus":"body","distance":3.5,"pose":{"right_elbow":110,"left_knee":55,"left_hip":30,"right_index":60},"show_regions":true})
    save_image("body-joints",await read());await frames(3);root.get_texture().get_image().save_png("res://lie27-sphere-overlay.png")
    await change({"focus":"face","distance":.35,"pose":{},"show_regions":true})
    await read();await frames(3);root.get_texture().get_image().save_png("res://lie27-face-overlay.png")
    check(lab.effect.get("asset_uploads")==1,"Expressions/fingers reuse one bank upload")
    var idle: int=lab.effect.get("frame_count");await frames(5);check(lab.effect.get("frame_count")==idle,"Stopped expression stays resident")
    for case in coverage["cases"]:
        if case["name"] not in ["half_closed","orbit_right","orbit_right_closed","orbit_left","orbit_left_closed"]:continue
        var controls: Dictionary=face();controls.merge(case["face"],true)
        await change({"focus":"face","distance":.35,"camera_yaw":case.get("camera_yaw",0),"pose":case["pose"],"face":controls,"show_regions":false})
        var data: Dictionary=await read();save_image(case["name"],data);verify_coverage(case["name"],data)
        if controls["blink_left"]==1.0 and controls["blink_right"]==1.0:
            var orbit_eyes: Dictionary=visible_eyes(data);report["eye_visibility_pixels"][case["name"]]=orbit_eyes
            check(orbit_eyes["left"]==0 and orbit_eyes["right"]==0,"Closed orbital view fully occludes both native eyes: "+str(case["name"]))
    await change({"camera_yaw":0,"pose":{},"face":face(),"mask":14})
    var exposed: Dictionary=await read();save_image("without-skin",exposed)
    var interior_pixels: int=0
    for owner in exposed["winners"]:
        if owner>=0 and sample_tags[owner*2] in [1,2]:interior_pixels+=1
    check(interior_pixels>1000,"Disabling skin still exposes native inner anatomy")
    await change({"mask":8});var ocular_before: Dictionary=await read()
    var palette: Array=lab.state["palette"].duplicate(true);palette[3]=[.01,.8,.2]
    await change({"palette":palette});var ocular_after: Dictionary=await read()
    check(same_eye_pixels(ocular_before,ocular_after),"Ocular color is independent from the interior palette")
    palette[3]=[.29,.12,.15];await change({"palette":palette,"mask":15})
    var eyes: Dictionary=lab.state["eyes"].duplicate(true);var brown: Dictionary=await read()
    eyes["iris"]=[.025,.12,.42];await change({"eyes":eyes});var blue: Dictionary=await read();save_image("eyes-blue",blue)
    check(blue["color"]!=brown["color"],"Iris color code changes the native eyes")
    check(same_non_eye_pixels(brown,blue),"Blue iris leaves skin and interior tissues unchanged")
    eyes["iris"]=[.035,.22,.06];await change({"eyes":eyes});var green: Dictionary=await read();save_image("eyes-green",green)
    check(same_non_eye_pixels(brown,green),"Green iris leaves skin and interior tissues unchanged")
    var revision_eye: int=lab.revision;eyes["iris"]=[NAN,0,0]
    check(not lab.command({"op":"set_values","values":{"eyes":eyes,"light_power":0}})["ok"] and lab.revision==revision_eye and lab.state["light_power"]==70,"Invalid ocular color rejects the whole transaction")
    eyes["iris"]=[.16,.06,.015];await change({"eyes":eyes})
    check(lab.effect.get("asset_uploads")==1,"Ocular codes reuse the resident capture bank")
    # A short deterministic cycle, genuinely produced by the compositor.
    DirAccess.make_dir_recursive_absolute("res://lie27-frames")
    for i in range(12):
        var amount: float=sin(i*PI/11)
        await change({"face":face(amount,amount),"show_regions":false})
        var data: Dictionary=await read();save_image("blink-%02d"%i,data)
    report.merge({"checks":checks,"failed":failed,"device":restored["device"],"allocation_bytes":restored["allocation_bytes"],"asset_uploads":lab.effect.get("asset_uploads"),"samples":lab.effect.get("master")["sample_count"],"bones":45,"joint_spheres":44,"facial_regions":9})
    var file:=FileAccess.open("res://lie27-diagnostic.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
    print("LIE27 GPU ","FAIL" if failed else "PASS"," ",checks," checks")
    lab.queue_free();await frames(2);quit(1 if failed else 0)
