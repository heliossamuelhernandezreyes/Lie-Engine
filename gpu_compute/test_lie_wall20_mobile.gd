extends "res://test_lie_wall12_mobile.gd"
const BoundsPool=preload("res://lie_shared_tangent_bounds.gd")
func run() -> void:
    var previous=load("res://lie_wall17_android_lab.tscn").instantiate();root.add_child(previous);await settle(16)
    check(previous.effect.gpu_ready,"actual 1.4 baseline ready")
    if not previous.effect.gpu_ready:printerr(previous.effect.failure);quit(1);return
    var baseline: Dictionary=await capture(previous.effect);previous.queue_free();await settle()
    var lab=load("res://lie_wall20_android_lab.tscn").instantiate();root.add_child(lab);await settle(16)
    check(lab.effect.gpu_ready and lab.effect._tangent_kernel_set.is_valid() and lab.effect._tangent_stream_set.is_valid(),"refitted original and diagnostic descriptor sets ready")
    if not lab.effect.gpu_ready:printerr(lab.effect.failure);quit(1);return
    var initial: Dictionary=await take(lab,"shipping");same(baseline,initial,"shipping matches accepted 1.4");check(baseline["depth"]==initial["depth"],"shipping exact depth")
    var memory: int=lab.effect.allocation_bytes;var bounds_rid: RID=lab.effect._tangent_lease["rid"];var borrowed: Dictionary={}
    RenderingServer.call_on_render_thread(func():borrowed.merge(BoundsPool.acquire(lab.effect._rd,lab.effect._tangent_document)))
    await settle();check(borrowed.get("rid",RID())==bounds_rid,"immutable refitted bounds shared by independent consumer lease")
    RenderingServer.call_on_render_thread(func():BoundsPool.release(lab.effect._rd,borrowed["key"]))
    await settle()
    for pose in [{"camera_yaw":-7.963168335,"camera_elevation":3.296510829,"distance_factor":1.,"light_azimuth":-24.,"lighting_preset":"neutral"},{"camera_yaw":80.},{"camera_yaw":150.},{"camera_yaw":-52.655622406,"camera_elevation":-7.350296603,"distance_factor":.6,"light_azimuth":-96.75,"light_power":1.46,"exposure":1.09,"energy_radius":true,"lighting_preset":"warm_raking"}]:
        pose["tight_bounds"]=false;pose["visibility_stream"]=false;lab.command({"op":"set_values","values":pose});lab.effect.force_geometry_rebuild();lab.effect.clear_visibility_cache();await settle();var reference: Dictionary=await take(lab,"off_"+str(pose["camera_yaw"]))
        lab.command({"op":"set_values","values":{"tight_bounds":true}});lab.effect.clear_visibility_cache();await settle();var candidate: Dictionary=await take(lab,"on_"+str(pose["camera_yaw"]))
        same(reference,candidate,"tight bounds preserve original image "+str(pose["camera_yaw"]));check(reference["depth"]==candidate["depth"],"tight bounds exact depth")
    lab.command({"op":"set_values","values":{"visibility_diagnostics":true}});await settle()
    var geometry: int=lab.effect.geometry_rebuilds
    lab.command({"op":"set_values","values":{"light_power":.9}});await settle();var power: Dictionary=await take(lab,"power")
    check(queries(power)==0 and lab.effect.geometry_rebuilds==geometry,"power reuses geometric visibility and geometry")
    for offset in [.01,.1,1.,8.]:
        lab.command({"op":"set_values","values":{"tight_bounds":true,"light_azimuth":-96.75+offset}});await settle();var candidate: Dictionary=await take(lab,"move_"+str(offset))
        lab.command({"op":"set_values","values":{"tight_bounds":false,"occlusion_witnesses":false}});lab.effect.clear_visibility_cache();await settle();var reference: Dictionary=await take(lab,"full_"+str(offset));same(reference,candidate,"moved light preserves original visibility "+str(offset))
        lab.command({"op":"set_values","values":{"occlusion_witnesses":true}});await settle()
    for options in [{"area_lights":true,"camera_yaw":12.,"distance_factor":1.},{"area_lights":false,"surface_continuity":false,"distance_factor":1.4},{"surface_continuity":true,"distance_factor":1.,"quality_2x":true},{"quality_2x":false,"active_visibility":false},{"active_visibility":true,"precomputed_ray_boxes":false}]:
        options["tight_bounds"]=false;lab.command({"op":"set_values","values":options});lab.effect.clear_visibility_cache();await settle();var reference: Dictionary=await capture(lab.effect)
        lab.command({"op":"set_values","values":{"tight_bounds":true}});lab.effect.clear_visibility_cache();await settle();var candidate: Dictionary=await capture(lab.effect)
        same(reference,candidate,"area/LOD/continuity/resize/queue/box paths preserve output");check(reference["depth"]==candidate["depth"],"option depth exact")
    # Match the supplied 1.6 physical report's scene for the new paired run.
    lab.command({"op":"set_values","values":{"quality_2x":false,"distance_factor":1.,"camera_yaw":-7.96316833496092,"camera_elevation":3.296510828865894,"light_azimuth":-24.,"light_power":1.,"exposure":2.,"energy_radius":false,"lighting_preset":"neutral","precomputed_ray_boxes":true,"visibility_diagnostics":false,"tight_bounds":false,"visibility_stream":false}});await settle()
    var backup: Dictionary=lab.state.duplicate(true);check(lab.command({"op":"compare_kernels"})["ok"],"paired original versus refitted bounds accepted")
    for i in range(20000):
        await process_frame
        if not lab.benchmark_busy:break
    var diagnostic: Dictionary=lab._comparison_report
    check(not lab.benchmark_busy and diagnostic.get("error","missing")=="" and diagnostic.get("restored",false) and lab.state==backup,"comparison completed and exact state restored")
    check(diagnostic.get("events",[]).size()==54 and diagnostic.get("warmup_events",[]).size()==60 and diagnostic.get("summary",[]).size()==6,"54 measured plus 60 separately retained warm-up events")
    for group in diagnostic.get("summary",[]):check(group["gpu"]["samples"]==9 and group["cpu"]["samples"]==9,"nine complete events in each paired group")
    var work: Array=diagnostic.get("work_diagnostic",[]);check(work.size()==6,"six separate untimed paired work events")
    if work.size()==6:
        for index in range(3):
            var before: Dictionary=work[index]["counters"];var after: Dictionary=work[index+3]["counters"]
            check(before.get("instrumented",false) and after.get("instrumented",false) and before.get("eligible",0)==after.get("eligible",-1) and before.get("unresolved_queries",0)==after.get("unresolved_queries",-1),"paired probes retain receiver/ray counts")
            check(after.get("blas_nodes",0)<before.get("blas_nodes",0) and after.get("disk_tests",0)<before.get("disk_tests",0),"actual Vulkan traversal visits fewer nodes and tests fewer disks")
    var portable: Dictionary=lab._portable_report(lab._build_report());check(JSON.stringify(portable).to_utf8_buffer().size()<16384 and portable["kernel_comparison"]["scene"]==backup,"paired scene, timings and both work variants fit copied report")
    lab.command({"op":"set_values","values":{"tight_bounds":true,"visibility_stream":true}});await settle();var streamed: Dictionary=await take(lab,"streamed")
    lab.command({"op":"set_values","values":{"tight_bounds":false,"visibility_stream":false}});await settle();var reference: Dictionary=await take(lab,"stream_reference");same(reference,streamed,"refit composes with separately instrumented stream")
    check(lab.effect._tangent_lease["rid"]==bounds_rid,"bounds lease retained across camera/lights/resize")
    var frames: int=lab.effect.frame_count;await settle(12)
    check(lab.effect.frame_count==frames and lab.effect.asset_uploads==1 and lab.effect.allocation_bytes==memory and lab.agent_snapshot()["collider_count"]==1,"cached idle, single bank/collider and stable allocation")
    report.merge({"checks":checks,"failed":failed,"device":reference["device"],"events":events,"comparison":diagnostic,"cache":lab.effect.cache_metrics(),"appearance_requested_bytes":memory,"source_bank_sha256":lab.effect.catalog["sha256"],"physical_android_tested":false})
    var file:=FileAccess.open("res://wall20-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    lab.queue_free();await settle();print("WALL20 ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
