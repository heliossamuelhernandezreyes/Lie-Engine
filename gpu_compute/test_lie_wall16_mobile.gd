extends "res://test_lie_wall12_mobile.gd"
func take_query(lab,label: String) -> Dictionary:
    var data: Dictionary=await take(lab,label)
    events[label]["surface_queries"]=data["surface_queries"]
    return data
func run() -> void:
    var old=load("res://lie_wall15_android_lab.tscn").instantiate();root.add_child(old);await settle(16)
    check(old.effect.gpu_ready,"accepted 1.2 baseline ready")
    if not old.effect.gpu_ready:quit(1);return
    var baseline: Dictionary=await capture(old.effect);old.queue_free();await settle()
    var lab=load("res://lie_wall16_android_lab.tscn").instantiate();root.add_child(lab);await settle(16)
    check(lab.effect.gpu_ready,"surface query runtime ready")
    if not lab.effect.gpu_ready:printerr(lab.effect.failure);quit(1);return
    lab.command({"op":"set_values","values":{"visibility_diagnostics":true}});await settle()
    var initial: Dictionary=await take_query(lab,"shipping");same(baseline,initial,"default 1.3 matches 1.2");check(baseline["depth"]==initial["depth"],"baseline exact depth")
    var initial_builds: int=lab.effect.bounds_builds;var memory: int=lab.effect.allocation_bytes
    var any_culled: bool=false
    for angle in [12.,60.,80.,150.,-80.]:
        lab.command({"op":"set_values","values":{"surface_queries":false,"occlusion_witnesses":false,"camera_yaw":angle}});lab.effect.force_geometry_rebuild();lab.effect.clear_visibility_cache();await settle();var reference: Dictionary=await take_query(lab,"reference_"+str(angle))
        lab.command({"op":"set_values","values":{"surface_queries":true,"occlusion_witnesses":true}});lab.effect.clear_visibility_cache();await settle();var query: Dictionary=await take_query(lab,"query_"+str(angle))
        same(reference,query,"hierarchy preserves all pixels "+str(angle));check(reference["depth"]==query["depth"],"hierarchy exact depth "+str(angle))
        any_culled=any_culled or query["surface_queries"]["selected_blocks"]<query["surface_queries"]["total_blocks"]
    check(any_culled,"hierarchy actually removes projection work")
    check(lab.effect.bounds_builds==initial_builds,"camera changes retain world derivation")
    lab.command({"op":"set_values","values":{"camera_yaw":12.,"light_azimuth":-72.,"light_power":1.2}});await settle()
    var benchmark: Array=[];var witness_hits: int=0
    for cycle in range(3):
        for optimized in [false,true]:
            lab.command({"op":"set_values","values":{"surface_queries":optimized,"occlusion_witnesses":optimized,"visibility_diagnostics":false,"light_azimuth":-72.}});await settle()
            lab.effect.force_geometry_rebuild();await settle();benchmark.append({"kind":"camera","optimized":optimized,"serial":lab.effect.frame_count})
            lab.command({"op":"set_values","values":{"light_azimuth":-71.8+cycle*.1}});await settle();benchmark.append({"kind":"light_position","optimized":optimized,"serial":lab.effect.frame_count})
    for offset in [0.,.01,.1,1.,8.]:
        lab.command({"op":"set_values","values":{"occlusion_witnesses":true,"visibility_diagnostics":true,"light_azimuth":-72.+offset}});await settle();var witness: Dictionary=await take_query(lab,"witness_"+str(offset));witness_hits+=witness["surface_queries"]["witness_hits"]
        lab.command({"op":"set_values","values":{"occlusion_witnesses":false}});lab.effect.clear_visibility_cache();await settle();var reference: Dictionary=await take_query(lab,"full_"+str(offset));same(reference,witness,"retested moving-light witnesses exact "+str(offset))
    check(witness_hits>0,"real photographed scene uses blocker certificates")
    lab.command({"op":"set_values","values":{"occlusion_witnesses":true,"area_lights":true,"lighting_preset":"warm_raking"}});await settle();var area: Dictionary=await take_query(lab,"area")
    lab.command({"op":"set_values","values":{"surface_queries":false,"occlusion_witnesses":false}});lab.effect.clear_visibility_cache();await settle();var area_ref: Dictionary=await take_query(lab,"area_reference");same(area_ref,area,"eight area channels preserve lighting")
    lab.command({"op":"set_values","values":{"surface_queries":true,"occlusion_witnesses":true,"surface_continuity":false,"distance_factor":1.4}});await settle();var lod: Dictionary=await take_query(lab,"lod")
    lab.command({"op":"set_values","values":{"surface_queries":false,"occlusion_witnesses":false}});lab.effect.clear_visibility_cache();await settle();var lod_ref: Dictionary=await take_query(lab,"lod_reference");same(lod_ref,lod,"LOD and reference-mode invalidation preserve image")
    lab.command({"op":"set_values","values":{"surface_queries":true,"occlusion_witnesses":true,"surface_continuity":true,"distance_factor":1.,"area_lights":false,"quality_2x":true,"key_enabled":false,"fill_enabled":false}});await settle();var black: Dictionary=await take_query(lab,"black")
    var energy: float=0.
    for i in range(0,black["color"].size(),4):
        for c in range(3):energy=maxf(energy,black["color"][i+c])
    check(energy<.00001 and black["internal_size"]==1440,"resize and lights off preserve darkness")
    lab.command({"op":"set_values","values":{"quality_2x":false,"key_enabled":true,"fill_enabled":true,"visibility_diagnostics":false}});await settle();var backup: Dictionary=lab.state.duplicate(true)
    check(lab.command({"op":"diagnose"})["ok"],"current-mode diagnostic accepted")
    for i in range(5000):
        await process_frame
        if not lab.benchmark_busy:break
    check(not lab.benchmark_busy and lab.state==backup and lab._diagnostic_report.get("restored",false),"diagnostic restores all query options")
    var portable: Dictionary=lab._portable_report(lab._build_report());check(portable["gpu_analysis"]["groups"].size()==3 and JSON.stringify(portable).to_utf8_buffer().size()<16384,"three diagnostic groups remain compact")
    await settle();var final: Dictionary=await take_query(lab,"final");var frames: int=lab.effect.frame_count;await settle(12)
    check(lab.effect.frame_count==frames and lab.effect.asset_uploads==1 and lab.agent_snapshot()["collider_count"]==1 and lab.effect.allocation_bytes==memory,"idle, immutable bank, single collider and stable allocation")
    report.merge({"checks":checks,"failed":failed,"device":final["device"],"events":events,"benchmark":benchmark,"passes":final["passes"],"cache":lab.effect.cache_metrics(),"appearance_requested_bytes":final["allocation_bytes"],"source_bank_sha256":lab.effect.catalog["sha256"],"physical_android_tested":false})
    var file:=FileAccess.open("res://wall16-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    lab.queue_free();await settle();print("WALL16 ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
