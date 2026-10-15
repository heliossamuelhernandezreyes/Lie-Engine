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
        "lod_distribution":house._metrics.get("lod_distribution",[]),
        "instances":data["instances"],"gpu_name":data["device"],
        "allocation_bytes":data["allocation_bytes"]}
    check(covered>60000 and bright>50000,"Real photographed wall density is maintained "+label)
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
    check(house._metrics.get("lod_distribution",[]).size()==3 and house._metrics["lod_distribution"][0]>0, "Actual LIE preassembled-wall 3-LOD with hero faces")
    check(house._metrics.get("sample_invocations",0)<=750000, "Shared material sample work within compositor GPU budget")
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
    # WALL05 cache adaptation. Every transition must be proved by
    # actual RD pass lists and by captured GPU output (never guessed FPS).
    var camera_cache: Dictionary=c.get("cache",{})
    check(camera_cache.get("geometry_rebuilds",0)>=3 and
        camera_cache.get("graph_rebuilds",999)==1,
        "Rotating camera preserves cross-panel graph across three views")
    check(house.command({"op":"set_values","values":{"light_power":1.25}}).get("ok",false),
        "Update RGB light power only")
    await _wait_frames(7)
    var light_only: Dictionary=await _read()
    check(not light_only.is_empty() and
        light_only.get("cache",{}).get("last_stages",[])==[8,10,4,6,11,12,7],
        "Power-only update skips camera projection, shadow and panel graph")
    check(light_only.get("cache",{}).get("geometry_rebuilds",-1)==camera_cache["geometry_rebuilds"] and
        light_only.get("cache",{}).get("graph_rebuilds",-1)==1,
        "Power change retains resident geometry and graph")
    check(house.command({"op":"set_values","values":{"light_azimuth":93.}}).get("ok",false),
        "Turn light with fixed viewpoint")
    await _wait_frames(7)
    var light_moved: Dictionary=await _read()
    var light_stages: Array=light_moved.get("cache",{}).get("last_stages",[])
    check(light_stages==[14,13,8,10,4,6,11,12,7],
        "Light direction regenerates ONLY the shadow atlas and shading")
    check(light_moved.get("cache",{}).get("graph_rebuilds",-1)==1,
        "Moving light preserves camera-independent panel graph")
    check(house.command({"op":"set_values","values":{"exposure":3.}}).get("ok",false),
        "Change final exposure")
    await _wait_frames(7)
    var exposure_only: Dictionary=await _read()
    check(exposure_only.get("cache",{}).get("last_stages",[])==[7],
        "Exposure-only executes final output without geometry or relighting")
    check(exposure_only.get("color",PackedFloat32Array())!=light_moved.get("color",PackedFloat32Array()),
        "Exposure-only changes displayed GPU pixels")
    check(house.command({"op":"set_values",
        "values":{"light_power":1.,"light_azimuth":110.,"exposure":2.65}}).get("ok",false),
        "Restore identical camera and light for resident A/B")
    await _wait_frames(7)
    var resident: Dictionary=await _read()
    var before_force: Dictionary=resident.get("cache",{})
    house.effect.force_geometry_rebuild()
    await _wait_frames(8)
    var cold: Dictionary=await _read()
    check(not cold.is_empty() and
        cold.get("cache",{}).get("geometry_rebuilds",0)>before_force.get("geometry_rebuilds",0) and
        cold.get("cache",{}).get("graph_rebuilds",0)>before_force.get("graph_rebuilds",0),
        "Full cold rebuild truly reprojects source and recomputes links")
    var max_cached_error: float=0.
    if not resident.is_empty() and not cold.is_empty():
        var cached_pixels: PackedFloat32Array=resident["color"]
        var fresh_pixels: PackedFloat32Array=cold["color"]
        if cached_pixels.size()==fresh_pixels.size():
            for k in range(cached_pixels.size()):
                max_cached_error=maxf(max_cached_error,absf(cached_pixels[k]-fresh_pixels[k]))
    check(max_cached_error<.002,
        "Cached relighting matches fully rebuilt Vulkan pixels within 0.002")
    output["reuse"]={"power_only":light_only.get("cache",{}).get("last_stages",[]),
        "moving_light":light_stages,
        "exposure_only":exposure_only.get("cache",{}).get("last_stages",[]),
        "cold_rebuild":cold.get("cache",{}).get("last_stages",[]),
        "max_absolute_pixel_error":max_cached_error,
        "graph_rebuilds_three_camera_views":camera_cache.get("graph_rebuilds",0)}
    var transport: Dictionary=c.get("multiwall_transport",{})
    check(transport.get("panels",0)==113 and transport.get("panels_with_bounce",0)>0,
        "Oriented cross-wall GPU transport actually receives positive bounced RGB")
    check(transport.get("energy_violations",999)==0,
        "Each emitter conserves normalized outgoing RGB transport")
    check(transport.get("active_links",0)>0 and transport.get("max_row_sum",99.)<=1.0001,
        "Occlusion-aware panel graph has physical nonnegative links")
    var disabled: Dictionary=house.command({"op":"set_values","values":{"bounce":false}})
    check(disabled.get("ok",false),"Independent GUI/agent control disables transport")
    await _wait_frames(7)
    var without: Dictionary=await _read()
    check(not without.is_empty() and without["color"]!=c["color"],
        "Identical camera/light changes native GPU pixels when bounce toggles")
    output["multiwall_transport"]=transport
    output["bounce_on_off_different"]=without.get("color",PackedFloat32Array())!=c.get("color",PackedFloat32Array())
    var no_bounce_image:=Image.create_from_data(without["output_size"],without["output_size"],
        false,Image.FORMAT_RGBAF,without["color"].to_byte_array())
    no_bounce_image.convert(Image.FORMAT_RGBA8)
    check(no_bounce_image.save_png("res://captures_out/lie37-no-bounce.png")==OK,
        "Native unbounced benchmark PNG")
    house.command({"op":"set_values","values":{"bounce":true}})
    await _wait_frames(7)
    var full: Dictionary=await _read()
    check(not full.is_empty(),"Same scene restored before seam control")
    check(house.command({"op":"set_values","values":{"seams":false}}).get("ok",false),
        "Independent seam micro-hole filter switch")
    await _wait_frames(7)
    var no_seams: Dictionary=await _read()
    var repaired: bool=not no_seams.is_empty() and no_seams["color"]!=full["color"]
    check(repaired,"Depth-normal-surface seam treatment changes actual pixels")
    output["seam_on_off_different"]=repaired
    if not no_seams.is_empty():
        var raw_img:=Image.create_from_data(no_seams["output_size"],no_seams["output_size"],
            false,Image.FORMAT_RGBAF,no_seams["color"].to_byte_array())
        raw_img.convert(Image.FORMAT_RGBA8)
        check(raw_img.save_png("res://captures_out/lie37-no-seam-repair.png")==OK,
            "Native raw-seam benchmark PNG")
    house.command({"op":"set_values","values":{"seams":true}})
    await _wait_frames(7)
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
        "views":output,"renderer":"LIE37 Vulkan captured-wall + 0.9 GGX + oriented cross-panel transport",
        "limits":"LLVMPipe software GPU, not mobile FPS; authentic brick+mortar, visual-only construction"}
    var f:=FileAccess.open("res://captures_out/lie36-native.json",FileAccess.WRITE)
    if f!=null:
        f.store_string(JSON.stringify(report,"  "))
        f.close()
    print("LIE36_NATIVE_REPORT "+JSON.stringify(report))
    house.queue_free()
    await _wait_frames(2)
    quit(1 if failed else 0)
