extends "res://test_lie_wall12_mobile.gd"
func run() -> void:
    var previous=load("res://lie_wall16_android_lab.tscn").instantiate();root.add_child(previous);await settle(16)
    check(previous.effect.gpu_ready,"actual 1.3 baseline ready")
    if not previous.effect.gpu_ready:printerr(previous.effect.failure);quit(1);return
    var baseline: Dictionary=await capture(previous.effect);previous.queue_free();await settle()
    var lab=load("res://lie_wall17_android_lab.tscn").instantiate();root.add_child(lab);await settle(16)
    check(lab.effect.gpu_ready and lab.effect._kernels_ready and lab.effect._kernels.size()==19,"18 dedicated kernels plus actual 1.2 pipeline ready")
    if not lab.effect.gpu_ready:printerr(lab.effect.failure);quit(1);return
    var initial: Dictionary=await take(lab,"shipping");same(baseline,initial,"default split matches actual 1.3");check(baseline["depth"]==initial["depth"],"default exact depth")
    var memory: int=lab.effect.allocation_bytes
    for pose in [{"camera_yaw":12.,"distance_factor":1.,"camera_elevation":7.},{"camera_yaw":60.},{"camera_yaw":80.},{"camera_yaw":150.},{"camera_yaw":-105.747891,"distance_factor":.6,"camera_elevation":3.54137,"light_azimuth":-88.52,"light_power":.75,"exposure":2.2}]:
        pose["kernel_mode"]="monolithic";lab.command({"op":"set_values","values":pose});lab.effect.force_geometry_rebuild();lab.effect.clear_visibility_cache();await settle();var reference: Dictionary=await take(lab,"mono_"+str(pose["camera_yaw"]))
        for mode in ["legacy","split"]:
            lab.command({"op":"set_values","values":{"kernel_mode":mode}});await settle();var candidate: Dictionary=await take(lab,mode+"_"+str(pose["camera_yaw"]))
            same(reference,candidate,"identical view across pipeline "+mode+str(pose["camera_yaw"]));check(reference["depth"]==candidate["depth"],"exact depth "+mode+str(pose["camera_yaw"]))
    for options in [{"camera_yaw":12.,"distance_factor":1.,"camera_elevation":7.,"area_lights":true},{"area_lights":false,"fused_shading":false,"surface_filter":false},{"fused_shading":true,"surface_filter":true,"surface_continuity":false,"distance_factor":1.4},{"surface_continuity":true,"distance_factor":1.,"quality_2x":true}]:
        options["kernel_mode"]="monolithic";lab.command({"op":"set_values","values":options});await settle();var reference: Dictionary=await capture(lab.effect)
        lab.command({"op":"set_values","values":{"kernel_mode":"split"}});await settle();var candidate: Dictionary=await capture(lab.effect)
        same(reference,candidate,"area/filter/continuity/LOD/resize preserve appearance");check(reference["depth"]==candidate["depth"],"option exact depth")
    lab.command({"op":"set_values","values":{"quality_2x":false,"distance_factor":.6,"camera_yaw":-105.747891,"camera_elevation":3.54137,"kernel_mode":"split"}});await settle()
    var backup: Dictionary=lab.state.duplicate(true)
    check(lab.command({"op":"compare_kernels","quick":true})["ok"],"paired diagnostic accepted")
    for i in range(10000):
        await process_frame
        if not lab.benchmark_busy:break
    var diagnostic: Dictionary=lab._comparison_report
    check(not lab.benchmark_busy and diagnostic.get("error","missing")=="" and diagnostic.get("restored",false) and lab.state==backup,"paired comparison completed and restored")
    check(diagnostic.get("events",[]).size()==27 and diagnostic.get("summary",[]).size()==9,"all three modes and event types measured")
    for entry in diagnostic.get("summary",[]):check(entry["gpu"]["samples"]==3 and entry["cpu"]["samples"]==3,"three complete matched events per group")
    var entries: Dictionary={}
    for event in diagnostic.get("events",[]):
        var key: String=str(event["cycle"])+"|"+event["kind"]
        if not entries.has(key):entries[key]={}
        if not entries[key].has(event["mode"]):entries[key][event["mode"]]=[]
        entries[key][event["mode"]].append(event["values"])
    for entry in entries.values():check(entry["legacy"]==entry["monolithic"] and entry["monolithic"]==entry["split"],"identical command sequence across modes")
    var portable: Dictionary=lab._portable_report(lab._build_report());check(JSON.stringify(portable).to_utf8_buffer().size()<16384 and portable["kernel_comparison"]["summary"].size()==9,"all paired summaries fit copied report")
    lab.command({"op":"set_values","values":{"key_enabled":false,"fill_enabled":false}});await settle();var black: Dictionary=await take(lab,"black");var energy: float=0.
    for i in range(0,black["color"].size(),4):
        for c in range(3):energy=maxf(energy,black["color"][i+c])
    check(energy<.00001,"sources off remain dark")
    var frames: int=lab.effect.frame_count;await settle(12)
    check(lab.effect.frame_count==frames and lab.effect.asset_uploads==1 and lab.effect.allocation_bytes==memory and lab.agent_snapshot()["collider_count"]==1,"idle, single bank/collider, stable surface buffer allocation")
    report.merge({"checks":checks,"failed":failed,"device":black["device"],"events":events,"comparison":diagnostic,"cache":lab.effect.cache_metrics(),"appearance_requested_bytes":memory,"source_bank_sha256":lab.effect.catalog["sha256"],"physical_android_tested":false})
    var file:=FileAccess.open("res://wall17-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    lab.queue_free();await settle();print("WALL17 ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
