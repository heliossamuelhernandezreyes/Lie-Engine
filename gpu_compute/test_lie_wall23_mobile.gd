extends "res://test_lie_wall12_mobile.gd"
func hdr(effect: CompositorEffect) -> PackedFloat32Array:
    var result: Dictionary={}
    RenderingServer.call_on_render_thread(func():result["bytes"]=effect._rd.texture_get_data(effect._images[9],0))
    for i in range(120):
        await process_frame
        if result.has("bytes"):return result["bytes"].to_float32_array()
    check(false,"HDR readback timeout");return PackedFloat32Array()
func same_hdr(a: PackedFloat32Array,b: PackedFloat32Array,label: String) -> void:
    var worst: float=INF;var absolute: float=INF
    if a.size()==b.size() and not a.is_empty():
        worst=0.;absolute=0.
        for i in range(a.size()):
            var delta: float=absf(a[i]-b[i]);absolute=maxf(absolute,delta);worst=maxf(worst,delta/maxf(1.,absf(a[i])))
    report[label]={"max_absolute":absolute,"max_scaled":worst}
    check(worst<.00002,label)
func compare_reference(lab,label: String) -> void:
    var cached: Dictionary=await take(lab,label+"_cached");var a: PackedFloat32Array=await hdr(lab.effect)
    lab.command({"op":"set_values","values":{"power_response":false}});await settle()
    var reference: Dictionary=await take(lab,label+"_reference");var b: PackedFloat32Array=await hdr(lab.effect)
    same(reference,cached,label+" image");same_hdr(b,a,label+" HDR")
    check(cached["depth"]==reference["depth"],label+" exact depth")
    lab.command({"op":"set_values","values":{"power_response":true}});await settle()
func pair(lab,values: Dictionary,label: String) -> void:
    values=values.duplicate(true);values["power_response"]=false;values["stage_timestamps"]=true;values["lean_barriers"]=false
    check(lab.command({"op":"set_values","values":values})["ok"],label+" controls");await settle()
    var a: Dictionary=await take(lab,label+"_reference");var ah: PackedFloat32Array=await hdr(lab.effect)
    var target: Dictionary={"light_power":lab.state["light_power"],"fill_power":lab.state["fill_power"]}
    var geometry: int=lab.effect.geometry_rebuilds;var builds: int=lab.effect.response_builds;var reuses: int=lab.effect.response_reuses
    lab.command({"op":"set_values","values":{"power_response":true}});await settle()
    lab.command({"op":"set_values","values":{"light_power":target["light_power"]*.81,"fill_power":target["fill_power"]*.77}});await settle()
    check(lab.effect.response_builds==builds+1,label+" first power change captures basis")
    lab.command({"op":"set_values","values":{"light_power":target["light_power"]*.67,"fill_power":target["fill_power"]*.59}});await settle()
    lab.command({"op":"set_values","values":target});await settle()
    var b: Dictionary=await take(lab,label+"_reused");var bh: PackedFloat32Array=await hdr(lab.effect)
    same(a,b,label+" image");same_hdr(ah,bh,label+" HDR")
    check(a["depth"]==b["depth"],label+" exact depth")
    check(lab.effect.geometry_rebuilds==geometry and lab.effect.response_builds==builds+1 and lab.effect.response_reuses>=reuses+2,label+" power reuses geometry and basis")
func run() -> void:
    var lab=load("res://lie_wall23_android_lab.tscn").instantiate();root.add_child(lab);await settle(16)
    check(lab.effect.gpu_ready and lab.transport.gpu_ready,"actual response compositor and shared transport ready")
    if not lab.effect.gpu_ready or not lab.transport.gpu_ready:printerr(lab.effect.failure);quit(1);return
    for pose in [
        {"camera_yaw":12.,"distance_factor":1.,"light_power":1.2},
        {"camera_yaw":-74.98607177734377,"camera_elevation":3.7558485666910815,"distance_factor":.6,"light_azimuth":85.48,"light_power":1.49},
        {"camera_yaw":60.,"energy_radius":true,"separate_lights":false,"material_response":false},
        {"camera_yaw":12.,"separate_lights":true,"material_response":true,"area_lights":true},
        {"area_lights":false,"energy_radius":false}]:await pair(lab,pose,"pose_"+str(events.size()))
    for values in [{"key_enabled":false},{"key_enabled":true,"fill_enabled":false},{"fill_enabled":true}]:
        lab.command({"op":"set_values","values":values});await settle();await compare_reference(lab,"lifetime_"+str(events.size()))
    for values in [{"camera_yaw":65.},{"light_azimuth":-40.},{"clay_absorption":.3},{"normal_filtering":false},{"surface_detail":false},{"quality_2x":true}]:
        var builds: int=lab.effect.response_builds
        lab.command({"op":"set_values","values":values});await settle()
        check(lab.effect._response_action=="reference" and lab.effect.response_builds==builds,"non-power edit uses original surface shader")
        await compare_reference(lab,"invalidate_"+str(events.size()))
    lab.command({"op":"set_values","values":{"quality_2x":false,"normal_filtering":true,"surface_detail":true,"clay_absorption":0.}});await settle()
    var baseline: Dictionary=await take(lab,"submission_reference")
    for values in [{"stage_timestamps":false},{"lean_barriers":true},{"stage_timestamps":true}]:
        lab.command({"op":"set_values","values":values});await settle()
        var changed: Dictionary=await take(lab,"submission_"+str(events.size()));same(baseline,changed,"submission mode image "+str(events.size()))
    check(lab.effect.lean_transitions>0,"experimental lean submission actually exercised")
    var backup: Dictionary=lab.state.duplicate(true)
    var quick: bool=OS.get_environment("LIE_RESPONSE_QUICK")=="1"
    check(lab.command({"op":"compare_kernels","quick":quick})["ok"],"isolated whole-interval comparison accepted")
    for i in range(30000):
        await process_frame
        if not lab.benchmark_busy:break
    var diagnostic: Dictionary=lab._comparison_report;var rounds: int=1 if quick else 4
    check(not lab.benchmark_busy and diagnostic.get("error","missing")=="" and diagnostic.get("restored",false) and lab.state==backup,"comparison completes and restores scene")
    check(diagnostic.get("events",[]).size()==rounds*36 and diagnostic.get("warmup_events",[]).size()==rounds*40 and diagnostic.get("summary",[]).size()==12,"all timed events and fixed warm-up retained")
    for group in diagnostic.get("summary",[]):check(group["gpu"]["samples"]==rounds*3 and group["cpu"]["samples"]==rounds*3,"complete whole GPU events in every group")
    var portable: Dictionary=lab._portable_report(lab._build_report())
    check(JSON.stringify(portable).to_utf8_buffer().size()<32768 and portable["kernel_comparison"]["scene"]==backup,"compact report preserves exact comparison scene")
    var frames: int=lab.effect.frame_count;await settle(12)
    check(lab.effect.frame_count==frames and lab.effect.asset_uploads==1 and lab.agent_snapshot()["collider_count"]==1 and lab.agent_snapshot()["metrics"]["visible_source_meshes"]==0,"idle cache, shared bank, single invisible collider")
    var final: Dictionary=await take(lab,"final");save_material(final,"power-response")
    report.merge({"checks":checks,"failed":failed,"device":final["device"],"events":events,"comparison":diagnostic,"cache":lab.effect.cache_metrics(),"appearance_requested_bytes":lab.effect.allocation_bytes,"physical_android_tested":false,"test_provenance":"reconstructed acceptance after temporary source loss; raw results are from this execution"})
    var file:=FileAccess.open("res://wall23-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    lab.queue_free();await settle();print("WALL23 ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
