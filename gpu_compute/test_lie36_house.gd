extends SceneTree
## Native Vulkan captures of the *actual* scanned-asset LIE compositor.
var checks: int=0
var failed: bool=false
var output: Dictionary={}
var house
func _initialize() -> void:call_deferred("_run")
func check(ok: bool,description: String) -> bool:
    checks+=1
    if not ok:
        failed=true
        push_error("LIE36 REAL HOUSE FAIL: "+description)
    return ok
func _wait_frames(n: int=5) -> void:
    for i in range(n):await process_frame
func _meshes(n: Node) -> int:
    var found: int=1 if n is MeshInstance3D else 0
    for c in n.get_children():found+=_meshes(c)
    return found
func _read() -> Dictionary:
    house.effect.request_readback()
    for j in range(240):
        await process_frame
        var data: Dictionary=house.effect.readback()
        if not data.is_empty():return data
    return {}
func _take(label: String, angle: float, elevation: float=18.) -> Dictionary:
    var reply: Dictionary=house.command({"op":"set_values",
        "values":{"camera_yaw":angle,"camera_elevation":elevation}})
    check(reply.get("ok",false),"Camera command "+label)
    await _wait_frames(7)
    var data: Dictionary=await _read()
    if data.is_empty():
        check(false,"GPU readback "+label)
        return {}
    var values: PackedFloat32Array=data["color"]
    var covered: int=0
    var bright: int=0
    for i in range(3,values.size(),4):
        if values[i]>.5:
            covered+=1
            if values[i-3]+values[i-2]+values[i-1]>.24:bright+=1
    output[label]={"covered_pixels":covered,"lit_pixels":bright,
        "sample_invocations":data["sample_invocations"],
        "instances":data["instances"],"gpu_name":data["device"],
        "allocation_bytes":data["allocation_bytes"]}
    check(covered>1200 and bright>700,"Real photographed surfaces render "+label)
    var img:=Image.create_from_data(data["output_size"],data["output_size"],
        false,Image.FORMAT_RGBAF,values.to_byte_array())
    img.convert(Image.FORMAT_RGBA8)
    check(img.save_png("res://captures_out/lie36-"+label+".png")==OK,"Real engine PNG "+label)
    print("LIE36_NATIVE_IMAGE "+label+" "+JSON.stringify(output[label]))
    return data
func _run() -> void:
    house=load("res://lie36_house_lab.tscn").instantiate()
    get_root().add_child(house)
    var eff: CompositorEffect=house.effect
    if not check(eff.capture_loaded,"Verified real source bank loaded"):
        printerr(eff.failure)
        quit(1)
        return
    check(house.house_plan.get("stories",0)==2 and house.house_plan.get("edges",0)==10,
        "Two-level L building with 10 exterior boundary edges")
    check(house._instances().size()>100 and house._instances().size()<=128,
        "Detailed house within generic LIE instance budget")
    check(_meshes(house)==0,"No original source mesh or rendered procedural substitute")
    for i in range(330):
        await process_frame
        if eff.gpu_ready and eff.frame_count>=1:break
    if not check(eff.gpu_ready and eff.frame_count>0,"Vulkan compositor actually executed"):
        printerr(eff.failure)
        quit(1)
        return
    var a: Dictionary=await _take("front",-165.,24.)
    var b: Dictionary=await _take("corner",-110.,20.)
    house.command({"op":"set_values","values":{"light_azimuth":110.}})
    var c: Dictionary=await _take("courtyard",115.,23.)
    if a.is_empty() or b.is_empty() or c.is_empty():
        quit(1)
        return
    check(a["color"]!=b["color"] and b["color"]!=c["color"],
        "Three true camera views show differing scanned surfaces")
    var no_roof: Dictionary=house.command({"op":"set_values","values":{"roof":false}})
    check(no_roof.get("ok",false),"Roof toggles")
    await _wait_frames(6)
    var d: Dictionary=await _read()
    check(not d.is_empty() and d["instances"]<c["instances"],
        "Actual roof samples removed without replacing source")
    output["roof_off_instances"]=d.get("instances",0)
    var report: Dictionary={"result":"pass" if not failed else "failure",
        "checks":checks,"device":a["device"],"samples":eff.catalog["sample_count"],
        "source":eff.catalog["source_bank_sha256"],
        "views":output,"renderer":"LIE28 GLSL actual captured-source Vulkan compute",
        "limits":"LLVMPipe software GPU, not mobile FPS; authentic brick+mortar, visual-only construction"}
    var f:=FileAccess.open("res://captures_out/lie36-native.json",FileAccess.WRITE)
    if f!=null:
        f.store_string(JSON.stringify(report,"  "))
        f.close()
    print("LIE36_NATIVE_REPORT "+JSON.stringify(report))
    house.queue_free()
    await _wait_frames(2)
    quit(1 if failed else 0)
