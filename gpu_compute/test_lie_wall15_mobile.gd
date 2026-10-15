extends "res://test_lie_wall12_mobile.gd"
func run() -> void:
    var old=load("res://lie_wall14_android_lab.tscn").instantiate();root.add_child(old);await settle(16)
    check(old.effect.gpu_ready,"accepted 1.1 baseline ready")
    if not old.effect.gpu_ready:quit(1);return
    var baseline: Dictionary=await capture(old.effect);old.queue_free();await settle()
    var lab=load("res://lie_wall15_android_lab.tscn").instantiate();root.add_child(lab);await settle(16)
    check(lab.effect.gpu_ready and lab.transport.gpu_ready,"active GPU runtime ready")
    if not lab.effect.gpu_ready:printerr(lab.effect.failure);quit(1);return
    lab.command({"op":"set_values","values":{"visibility_diagnostics":true}});await settle()
    var shipping: Dictionary=await take(lab,"shipping");same(baseline,shipping,"default active runtime preserves 1.1")
    var queue: Dictionary=shipping["active_work"]
    check(queue["count"]>0 and queue["count"]<queue["source_work"] and queue["groups"]==ceili(float(queue["count"])/64.),"bounded GPU queue contains fewer actual winning projections")
    var memory: int=lab.effect.allocation_bytes;var builds: int=lab.effect.queue_builds
    lab.command({"op":"set_values","values":{"light_power":1.2}});await settle();var powered: Dictionary=await take(lab,"power")
    check(lab.effect.queue_builds==builds and queries(powered)==0,"power reuses winner queue and geometric visibility")
    lab.command({"op":"set_values","values":{"visibility_diagnostics":true}});await settle()
    for angle in [12.,60.,80.]:
        lab.command({"op":"set_values","values":{"camera_yaw":angle,"active_visibility":false,"precomputed_ray_boxes":false,"cpu_reuse":false}});lab.effect.clear_visibility_cache();await settle();var reference: Dictionary=await take(lab,"reference_"+str(angle))
        lab.command({"op":"set_values","values":{"active_visibility":true,"precomputed_ray_boxes":false,"cpu_reuse":true}});lab.effect.clear_visibility_cache();await settle();var active: Dictionary=await take(lab,"active_"+str(angle))
        same(reference,active,"final-winner compaction exact at "+str(angle));check(reference["depth"]==active["depth"],"compaction preserves depth "+str(angle))
        check(queries(active)<=queries(reference),"only needed surface identities traced "+str(angle))
        lab.command({"op":"set_values","values":{"precomputed_ray_boxes":true}});await settle();var fast: Dictionary=await take(lab,"fast_"+str(angle))
        same(reference,fast,"precomputed broadphase preserves captured visibility "+str(angle))
    lab.command({"op":"set_values","values":{"camera_yaw":12.,"lighting_preset":"warm_raking","light_azimuth":-72.,"area_lights":true}});await settle();var area: Dictionary=await take(lab,"area_fast")
    lab.command({"op":"set_values","values":{"active_visibility":false,"precomputed_ray_boxes":false,"cpu_reuse":false}});lab.effect.clear_visibility_cache();await settle();var area_ref: Dictionary=await take(lab,"area_reference")
    same(area_ref,area,"all eight finite-source channels preserve image and coverage")
    lab.command({"op":"set_values","values":{"key_enabled":false,"fill_enabled":false,"active_visibility":true,"precomputed_ray_boxes":true,"cpu_reuse":true}});await settle();var black: Dictionary=await take(lab,"black")
    var energy: float=0.
    for i in range(0,black["color"].size(),4):
        for c in range(3):energy=maxf(energy,black["color"][i+c])
    check(energy<.00001,"zero sources remain dark")
    lab.command({"op":"set_values","values":{"key_enabled":true,"fill_enabled":true,"area_lights":false,"quality_2x":true}});await settle();var resized: Dictionary=await take(lab,"resized")
    check(resized["internal_size"]==1440 and lab.effect.asset_uploads==1 and resized["active_work"]["count"]<=lab.effect.MAX_WORK,"queue survives image resize without bank upload")
    lab.command({"op":"set_values","values":{"quality_2x":false,"visibility_diagnostics":false}});await settle()
    var cpu: Array=[];var gpu: Array=[]
    # Interleave comparison modes at the same camera. Each moved-light sample
    # has a new source position; record the separate queue-build/trace stages.
    for cycle in range(3):
        for fast in [false,true]:
            lab.command({"op":"set_values","values":{"cpu_reuse":fast,"active_visibility":fast,"precomputed_ray_boxes":fast}});await settle()
            for kind in ["camera","light_power","light_position"]:
                var values: Dictionary={"camera_yaw":12.+cycle*2.} if kind=="camera" else {"light_power":1.+cycle*.1} if kind=="light_power" else {"light_azimuth":-70.+cycle*7.}
                # Force a distinct target even if a previous interleaved mode
                # left the same control there, without timing that reset.
                var field: String=values.keys()[0];var desired: float=values[field]
                lab.command({"op":"set_values","values":{field:desired+.5 if field!="light_power" else desired+.05}});await settle()
                var begin: int=Time.get_ticks_usec();var result: Dictionary=lab.command({"op":"set_values","values":values});var elapsed: float=float(Time.get_ticks_usec()-begin)/1000.
                check(result["ok"],"benchmark command accepted")
                await settle();cpu.append({"kind":kind,"optimized":fast,"ms":elapsed,"revision":lab.revision});gpu.append({"kind":kind,"optimized":fast,"serial":lab.effect.frame_count})
    lab.command({"op":"set_values","values":{"cpu_reuse":true,"active_visibility":true,"precomputed_ray_boxes":true}});await settle()
    var backup: Dictionary=lab.state.duplicate(true);check(lab.command({"op":"diagnose"})["ok"],"new options participate in current-mode diagnostic")
    for i in range(5000):
        await process_frame
        if not lab.benchmark_busy:break
    check(not lab.benchmark_busy and lab._diagnostic_report.get("events",[]).size()==9 and lab._diagnostic_report.get("restored",false) and lab.state==backup,"diagnostic restores optimization controls and scene")
    await settle();var final: Dictionary=await take(lab,"final")
    check(lab.effect.allocation_bytes==memory and lab.effect.asset_uploads==1 and lab.agent_snapshot()["collider_count"]==1,"fixed additional queue allocation, one bank and one collider")
    var frames: int=lab.effect.frame_count;await settle(12);check(lab.effect.frame_count==frames,"idle remains cached")
    report.merge({"checks":checks,"failed":failed,"device":final["device"],"events":events,"cpu_benchmark":cpu,"gpu_benchmark":gpu,"passes":final["passes"],"cpu_stages":lab._build_report()["cpu_stages"],"appearance_requested_bytes":final["allocation_bytes"],"source_bank_sha256":lab.effect.catalog["sha256"],"physical_android_tested":false})
    var file:=FileAccess.open("res://wall15-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    lab.queue_free();await settle();print("WALL15 ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
