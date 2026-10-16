extends "res://test_lie_wall12_mobile.gd"
func raster_state(effect: CompositorEffect) -> Dictionary:
    var result: Dictionary={}
    RenderingServer.call_on_render_thread(func():
        result["owners"]=effect._rd.buffer_get_data(effect._buffers[5]);result["accumulated"]=effect._rd.buffer_get_data(effect._buffers[7]))
    for i in range(120):
        await process_frame
        if result.has("accumulated"):return result
    check(false,"raster readback timeout");return result
func pair(lab,values: Dictionary,label: String) -> void:
    values=values.duplicate(true);values["screen_tiles"]=false
    check(lab.command({"op":"set_values","values":values})["ok"],label+" controls")
    lab.effect.force_geometry_rebuild();lab.effect.clear_visibility_cache();await settle()
    var a: Dictionary=await take(lab,label+"_reference");var ar: Dictionary=await raster_state(lab.effect)
    lab.command({"op":"set_values","values":{"screen_tiles":true}});lab.effect.clear_visibility_cache();await settle()
    var b: Dictionary=await take(lab,label+"_tiles");var br: Dictionary=await raster_state(lab.effect)
    same(a,b,label+" image");check(a["depth"]==b["depth"],label+" exact depth")
    check(ar["owners"]==br["owners"],label+" exact lowest-ID ownership including ties")
    check(ar["accumulated"]==br["accumulated"],label+" exact integer albedo/normal/roughness sums")
func run() -> void:
    var old=load("res://lie_wall17_android_lab.tscn").instantiate();root.add_child(old);await settle(16)
    check(old.effect.gpu_ready,"actual 1.4 ready")
    if not old.effect.gpu_ready:printerr(old.effect.failure);quit(1);return
    var baseline: Dictionary=await capture(old.effect);old.queue_free();await settle()
    var lab=load("res://lie_wall22_android_lab.tscn").instantiate();root.add_child(lab);await settle(16)
    check(lab.effect.gpu_ready and lab.effect._tile_sets.size()==6,"six actual tile pipelines ready")
    if not lab.effect.gpu_ready:printerr(lab.effect.failure);quit(1);return
    var initial: Dictionary=await take(lab,"shipping");same(baseline,initial,"shipping reference preserves 1.4")
    for pose in [
        {"camera_yaw":12.,"distance_factor":1.},
        {"camera_yaw":80.},
        {"camera_yaw":150.},
        {"camera_yaw":-76.88014526367184,"camera_elevation":5.725764499240451,"distance_factor":.6,"light_azimuth":-96.29,"energy_radius":false},
        {"camera_yaw":-52.655622406,"camera_elevation":-7.350296603,"distance_factor":.6,"energy_radius":true,"surface_continuity":false},
        {"surface_continuity":true,"bounded_raster":false,"block_access":false,"surface_queries":false,"distance_factor":1.4},
        {"bounded_raster":true,"block_access":true,"surface_queries":true,"quality_2x":true,"distance_factor":1.},
        {"quality_2x":false,"tight_bounds":true,"area_lights":true,"camera_yaw":12.},
        {"area_lights":false,"compact_shadows":true,"visibility_stream":true}]:
        await pair(lab,pose,"pose_"+str(events.size()))
    lab.command({"op":"set_values","values":{"screen_tiles":true,"visibility_stream":false,"compact_shadows":false,"tight_bounds":false,"quality_2x":false,"distance_factor":.6,"camera_yaw":-76.88014526367184,"camera_elevation":5.725764499240451,"light_azimuth":-96.29,"light_power":1.,"energy_radius":false,"exposure":2.,"lighting_preset":"neutral"}});await settle()
    var builds: int=lab.effect.tile_builds;var allocations: int=lab.effect.tile_allocations
    for values in [{"light_power":1.3},{"light_azimuth":-90.},{"exposure":1.7}]:
        lab.command({"op":"set_values","values":values});await settle()
        check(lab.effect.tile_builds==builds and lab.effect.tile_allocations==allocations,"light/power/exposure reuse screen lists and allocations")
    var backup: Dictionary=lab.state.duplicate(true);check(lab.command({"op":"compare_kernels"})["ok"],"four-mode comparison accepted")
    for i in range(30000):
        await process_frame
        if not lab.benchmark_busy:break
    var diagnostic: Dictionary=lab._comparison_report
    check(not lab.benchmark_busy and diagnostic.get("error","missing")=="" and diagnostic.get("restored",false) and lab.state==backup,"four-mode completion and exact scene restoration")
    check(diagnostic.get("events",[]).size()==144 and diagnostic.get("warmup_events",[]).size()==160 and diagnostic.get("summary",[]).size()==12,"144 measured and 160 separately retained warm-up events")
    for group in diagnostic.get("summary",[]):check(group["gpu"]["samples"]==12 and group["cpu"]["samples"]==12,"twelve complete events per isolated mode/kind")
    var portable: Dictionary=lab._portable_report(lab._build_report());check(JSON.stringify(portable).to_utf8_buffer().size()<32768 and portable["kernel_comparison"]["scene"]==backup,"matrix evidence fits copied report")
    check(diagnostic.get("work_diagnostic",[]).size()==6,"six separate work probes for original/tight bounds")
    var frames: int=lab.effect.frame_count;await settle(12)
    check(lab.effect.frame_count==frames and lab.effect.asset_uploads==1 and lab.agent_snapshot()["collider_count"]==1 and lab.agent_snapshot()["metrics"]["visible_source_meshes"]==0,"cached idle, one source bank and one invisible collider")
    var final: Dictionary=await take(lab,"final");save_material(final,"screen-tiles")
    report.merge({"checks":checks,"failed":failed,"device":final["device"],"events":events,"comparison":diagnostic,"cache":lab.effect.cache_metrics(),"appearance_requested_bytes":lab.effect.allocation_bytes,"physical_android_tested":false})
    var file:=FileAccess.open("res://wall22-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    lab.queue_free();await settle();print("WALL22 ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
