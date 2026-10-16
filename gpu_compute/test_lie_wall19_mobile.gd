extends "res://test_lie_wall12_mobile.gd"
const OrderPool=preload("res://lie_shared_visibility_order.gd")
func take_stream(lab,label: String) -> Dictionary:
    return await take(lab,label)
func run() -> void:
    var previous=load("res://lie_wall17_android_lab.tscn").instantiate();root.add_child(previous);await settle(16)
    check(previous.effect.gpu_ready,"actual 1.4 baseline ready")
    if not previous.effect.gpu_ready:printerr(previous.effect.failure);quit(1);return
    var baseline: Dictionary=await capture(previous.effect);previous.queue_free();await settle()
    var lab=load("res://lie_wall19_android_lab.tscn").instantiate();root.add_child(lab);await settle(16)
    check(lab.effect.gpu_ready and lab.effect._stream_sets.size()==5,"stream kernels ready")
    if not lab.effect.gpu_ready:printerr(lab.effect.failure);quit(1);return
    var initial: Dictionary=await take_stream(lab,"shipping");same(baseline,initial,"shipping matches accepted 1.4");check(baseline["depth"]==initial["depth"],"unchanged projection exact depth")
    var memory: int=lab.effect.allocation_bytes;var order_rid: RID=lab.effect._order_lease["rid"]
    # Acquire a second render-thread consumer lease without a second world.
    var borrowed: Dictionary={}
    RenderingServer.call_on_render_thread(func():borrowed.merge(OrderPool.acquire(lab.effect._rd,lab.effect._stream_document)))
    await settle()
    check(borrowed.get("rid",RID()).is_valid() and borrowed["rid"]==order_rid and OrderPool.metrics(lab.effect._order_lease["key"])["references"]==2,"query-order RID shared between consumer leases")
    RenderingServer.call_on_render_thread(func():OrderPool.release(lab.effect._rd,borrowed["key"]))
    await settle();check(OrderPool.metrics(lab.effect._order_lease["key"])["references"]==1,"borrowed query-order lease released independently")
    lab.command({"op":"set_values","values":{"visibility_diagnostics":true}});await settle()
    for pose in [{"camera_yaw":12.,"distance_factor":1.},{"camera_yaw":80.},{"camera_yaw":150.},{"camera_yaw":-52.655622406,"camera_elevation":-7.350296603,"distance_factor":.6,"light_azimuth":-96.75,"light_power":1.46,"exposure":1.09,"energy_radius":true,"lighting_preset":"warm_raking"}]:
        pose["visibility_stream"]=false;lab.command({"op":"set_values","values":pose});lab.effect.force_geometry_rebuild();lab.effect.clear_visibility_cache();await settle();var reference: Dictionary=await take_stream(lab,"off_"+str(pose["camera_yaw"]))
        lab.command({"op":"set_values","values":{"visibility_stream":true}});lab.effect.clear_visibility_cache();await settle();var candidate: Dictionary=await take_stream(lab,"on_"+str(pose["camera_yaw"]))
        same(reference,candidate,"stream view preserves image "+str(pose["camera_yaw"]));check(reference["depth"]==candidate["depth"],"stream view exact depth")
    lab.effect.request_work_counters();await settle();var prior: Dictionary=lab.effect.work_counters()
    lab.command({"op":"set_values","values":{"light_power":.9}});await settle();var power: Dictionary=await take_stream(lab,"power")
    lab.effect.request_work_counters();await settle();var power_work: Dictionary=lab.effect.work_counters()
    check(power_work.get("unresolved_queries",-1)==0 and power_work.get("disk_tests",-1)==0 and power_work.get("cache_hits",0)>0,"power reuses visibility before the BLAS kernel")
    for offset in [.01,.1,1.,8.]:
        lab.command({"op":"set_values","values":{"visibility_stream":true,"light_azimuth":-96.75+offset}});await settle();var candidate: Dictionary=await take_stream(lab,"move_"+str(offset))
        lab.command({"op":"set_values","values":{"visibility_stream":false,"occlusion_witnesses":false}});lab.effect.clear_visibility_cache();await settle();var reference: Dictionary=await take_stream(lab,"full_"+str(offset));same(reference,candidate,"moved light preserves exact visibility "+str(offset))
        lab.command({"op":"set_values","values":{"occlusion_witnesses":true}});await settle()
    for options in [{"area_lights":true,"camera_yaw":12.,"distance_factor":1.},{"area_lights":false,"surface_continuity":false,"distance_factor":1.4},{"surface_continuity":true,"distance_factor":1.,"quality_2x":true}]:
        options["visibility_stream"]=false;lab.command({"op":"set_values","values":options});lab.effect.clear_visibility_cache();await settle();var reference: Dictionary=await capture(lab.effect)
        lab.command({"op":"set_values","values":{"visibility_stream":true}});lab.effect.clear_visibility_cache();await settle();var candidate: Dictionary=await capture(lab.effect)
        same(reference,candidate,"area/LOD/continuity/resize preserve output");check(reference["depth"]==candidate["depth"],"option depth exact")
    lab.command({"op":"set_values","values":{"quality_2x":false,"distance_factor":.6,"camera_yaw":-52.655622406005804,"camera_elevation":-7.3502966033088075,"light_azimuth":-96.75,"light_power":1.46,"exposure":1.09,"energy_radius":true,"lighting_preset":"warm_raking","visibility_diagnostics":false}});await settle()
    var backup: Dictionary=lab.state.duplicate(true);check(lab.command({"op":"compare_kernels"})["ok"],"paired stream diagnostic accepted")
    for i in range(20000):
        await process_frame
        if not lab.benchmark_busy:break
    var diagnostic: Dictionary=lab._comparison_report
    check(not lab.benchmark_busy and diagnostic.get("error","missing")=="" and diagnostic.get("restored",false) and lab.state==backup,"comparison completed and exact state restored")
    check(diagnostic.get("events",[]).size()==54 and diagnostic.get("warmup_events",[]).size()==60 and diagnostic.get("summary",[]).size()==6,"54 measured events plus 60 separately retained warm-up events")
    for group in diagnostic.get("summary",[]):check(group["gpu"]["samples"]==9 and group["cpu"]["samples"]==9,"nine complete events in each paired group")
    check(diagnostic.get("work_diagnostic",[]).size()==3,"three separate untimed work counter events")
    for entry in diagnostic.get("work_diagnostic",[]):
        var counters: Dictionary=entry["counters"];check(counters.get("available",false) and counters.get("instrumented",false) and counters.get("unresolved_queries",0)>0 and counters.get("blas_nodes",0)>0,"real trace work counters available")
    var portable: Dictionary=lab._portable_report(lab._build_report());check(JSON.stringify(portable).to_utf8_buffer().size()<16384 and portable["kernel_comparison"]["scene"]==backup,"all groups, cold summary and exact paired scene fit copied report")
    lab.command({"op":"set_values","values":{"visibility_stream":true,"active_visibility":false}});await settle();var inactive: Dictionary=await take_stream(lab,"inactive_fallback")
    lab.command({"op":"set_values","values":{"visibility_stream":false}});await settle();var original: Dictionary=await take_stream(lab,"inactive_reference");same(original,inactive,"inactive queue falls back to actual reference")
    lab.command({"op":"set_values","values":{"visibility_stream":true,"active_visibility":true}});await settle()
    lab.command({"op":"set_values","values":{"key_enabled":false,"fill_enabled":false}});await settle();var black: Dictionary=await take_stream(lab,"black");var energy: float=0.
    for i in range(0,black["color"].size(),4):
        for c in range(3):energy=maxf(energy,black["color"][i+c])
    check(energy<.00001,"no energy when sources are off")
    check(lab.effect._order_lease["rid"]==order_rid,"immutable query order retained across camera/lights/resize")
    var frames: int=lab.effect.frame_count;await settle(12)
    check(lab.effect.frame_count==frames and lab.effect.asset_uploads==1 and lab.effect.allocation_bytes==memory and lab.agent_snapshot()["collider_count"]==1,"cached idle, single bank/collider and stable allocation")
    report.merge({"checks":checks,"failed":failed,"device":black["device"],"events":events,"comparison":diagnostic,"cache":lab.effect.cache_metrics(),"appearance_requested_bytes":memory,"source_bank_sha256":lab.effect.catalog["sha256"],"physical_android_tested":false})
    var file:=FileAccess.open("res://wall19-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    lab.queue_free();await settle();print("WALL19 ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
