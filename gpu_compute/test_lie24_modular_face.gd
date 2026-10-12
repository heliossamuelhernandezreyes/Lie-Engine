extends "res://test_lie23_face.gd"
const ModularLab=preload("res://lie24_modular_face_lab.gd")
func run() -> void:
    lab=ModularLab.new();root.add_child(lab);command({"camera_yaw":0});await frames(12)
    check(lab.effect.get("capture_loaded") and lab.effect.get("gpu_ready"),"Actual Vulkan modular captures loaded")
    if failed:quit(1);return
    check(meshes(lab)==0,"All authoring surfaces remain invisible")
    check(fit(lab.ui),"Modular inspector fits the window")
    var m: Dictionary=lab.effect.get("master")
    check(m["vertex_count"]<m["original_vertex_count"],"Rigid captures reduce deformation vertices")
    check(m["rigid_face_sample_count"]>100000,"Rigid facial samples retain XYZ without dense cage")
    check(m["sample_count"]==m["face_sample_count"]+m["eye_sample_count"],"One eye library is shared")
    var source: PackedFloat32Array=lab.effect.get("_input")[2].to_float32_array()
    var triangles: PackedInt32Array=lab.effect.get("_input")[1].to_int32_array()
    var oracle: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://captures/face24/native-oracle.json"))
    var max_error: float=0;var inactive_owners: int=0;report={"native_cases":[]}
    for case in oracle["cases"]:
        command({"nose_index":case["nose_index"],"camera_yaw":case["camera_yaw"],"head_yaw":case["head_yaw"],"blink":case["blink"]});await frames()
        var data: Dictionary=await read_gpu(true);var projected: PackedFloat32Array=data["projected"];var error: float=0
        for probe in case["probes"]:
            var offset: int=int(probe["sample"])*24;var p: Array=probe["position"]
            error=maxf(error,Vector3(projected[offset],projected[offset+1],projected[offset+2]).distance_to(Vector3(p[0],p[1],p[2])))
        max_error=maxf(max_error,error);check(error<.00002,"Native assembled module/head/lid positions")
        var inactive: int=0
        for owner in data["winners"]:
            if owner>=int(m["face_sample_count"]):continue
            var ti: int=int(source[owner*20+3])
            if ti<0:continue
            var group: int=triangles[ti*4+3]
            if group>0 and group!=int(case["nose_index"])+1:inactive+=1
        inactive_owners+=inactive;check(inactive==0,"Inactive facial assets have no pixel ownership")
        if case["camera_yaw"]==0 and case["blink"]==0:
            var eyes: Array=visible_eyes(data);check(eyes[0]>100 and eyes[1]>100,"Nasal slot preserves both orbital openings")
        var suppressed: bool=true
        for module in m["facial_modules"]:
            if module["id"]==case["nose_index"]:continue
            for i in range(int(module["sample_offset"]),int(module["sample_offset"])+int(module["sample_count"])):
                if projected[i*24+3]!=0:suppressed=false;break
        check(suppressed,"Inactive modules have no projection or shadow contribution")
        if case["render"]:
            var img:=Image.create_from_data(512,512,false,Image.FORMAT_RGBAF,data["color"].to_byte_array());img.convert(Image.FORMAT_RGBA8);img.save_png("res://lie24-"+case["code"]+"-beauty.png")
            lab.diagnostic_mode=1;lab._apply();await frames();var albedo: Dictionary=await read_gpu()
            img=Image.create_from_data(512,512,false,Image.FORMAT_RGBAF,albedo["color"].to_byte_array());img.convert(Image.FORMAT_RGBA8);img.save_png("res://lie24-"+case["code"]+"-albedo.png")
            lab.diagnostic_mode=0;lab._apply()
        if case["blink"]==1:check(visible_eyes(data)==[0,0],"Detailed lids still cover both shared eyes")
        report["native_cases"].append({"code":case["code"],"position_error_m":error,"inactive_owners":inactive})
    command({"nose_index":1,"camera_yaw":0,"head_yaw":0,"blink":0});await frames();var classic: Dictionary=await read_gpu()
    command({"nose_index":2});await frames();var short_nose: Dictionary=await read_gpu()
    check(difference(classic,short_nose)>10,"Changing captured asset changes actual rendered image")
    command({"nose_index":1});await frames();var restored: Dictionary=await read_gpu()
    check(difference(classic,restored)==0,"Switching back restores identical image")
    check(restored["asset_uploads"]==1,"Switching variants needs no capture uploads")
    var packet: PackedByteArray=lab.effect.get("_parameters").duplicate();packet.encode_float(120,1.5)
    check(not lab.effect.call("configure",packet),"GPU boundary rejects fractional module ID")
    packet.encode_float(120,4);check(not lab.effect.call("configure",packet),"GPU boundary rejects missing module ID")
    DirAccess.make_dir_recursive_absolute("user://face24-contract-test")
    for invalid in ["family","overlap"]:
        var fixture: Dictionary=m.duplicate(true)
        if invalid=="family":fixture["facial_modules"][1]["family"]="another-head"
        else:fixture["facial_modules"][1]["sample_offset"]-=1
        var manifest_file:=FileAccess.open("user://face24-contract-test/master.json",FileAccess.WRITE)
        manifest_file.store_string(JSON.stringify(fixture));manifest_file.close()
        var rejected:=preload("res://lie23_face_effect.gd").new(128,1,"user://face24-contract-test/")
        check(not rejected.capture_loaded and rejected.failure.contains("incompatible" if invalid=="family" else "Rango facial"),"Reject incompatible family or overlapping slot range")
    var snapshot: Dictionary=lab.agent_snapshot();check(snapshot["nose_choices"]==[0,1,2,3] and snapshot["inbox"].contains("/face24/"),"Agent protocol exposes modular contract")
    root.get_texture().get_image().save_png("res://lie24-workshop.png")
    # Neutral presentation frames make shape differences easy to inspect.
    # Raw default lighting frames and independent native references remain
    # in the evidence; this lighting preset is not a performance benchmark.
    command({"light_azimuth":-8,"shadows":false})
    for nose in range(4):
        for yaw in [0,45,90]:
            command({"nose_index":nose,"camera_yaw":yaw});await frames();var portrait: Dictionary=await read_gpu()
            var img:=Image.create_from_data(512,512,false,Image.FORMAT_RGBAF,portrait["color"].to_byte_array());img.convert(Image.FORMAT_RGBA8)
            img.save_png("res://lie24-nose-%d-yaw-%d-presentation.png"%[nose,yaw])
    report.merge({"checks":checks,"failed":failed,"max_native_position_error_m":max_error,"inactive_owners":inactive_owners,
        "vertex_count":m["vertex_count"],"original_vertex_count":m["original_vertex_count"],"triangle_count":m["triangle_count"],
        "stored_samples":m["sample_count"],"invocations":m["invocation_count"],"allocation_bytes":restored["allocation_bytes"],
        "asset_uploads":restored["asset_uploads"],"device":restored["device"],"profile":restored["profile"]},true)
    var file:=FileAccess.open("res://lie24-diagnostic.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
    print("LIE24 GPU ","FAIL" if failed else "PASS"," ",checks," checks ",JSON.stringify(report));quit(1 if failed else 0)
