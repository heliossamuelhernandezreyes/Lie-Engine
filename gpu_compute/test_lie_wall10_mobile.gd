extends "res://test_lie_wall07_mobile.gd"
func save_source(data: Dictionary,name: String) -> void:
    var image:=Image.create_from_data(data["output_size"],data["output_size"],false,Image.FORMAT_RGBAF,data["color"].to_byte_array());image.convert(Image.FORMAT_RGBA8);image.save_png("res://wall10-"+name+".png")
func finite_image(data: Dictionary) -> bool:
    for v in data["color"]:
        if not is_finite(v) or v<0.:return false
    return true
func run() -> void:
    var old=load("res://lie_wall09_android_lab.tscn").instantiate();root.add_child(old);await settle(16)
    check(old.effect.gpu_ready and old.transport.gpu_ready,"accepted WALL09 baseline ready")
    if not old.effect.gpu_ready:printerr(old.effect.failure);quit(1);return
    var baseline: Dictionary=await capture(old.effect);old.queue_free();await settle()
    var lab=load("res://lie_wall10_android_lab.tscn").instantiate();root.add_child(lab);await settle(16)
    check(lab.effect.gpu_ready and lab.transport.gpu_ready,"source BVH and source-ID cache ready")
    if not lab.effect.gpu_ready:printerr(lab.effect.failure);quit(1);return
    check(lab.command({"op":"set_values","values":{"surface_continuity":false,"world_contacts":false}})["ok"],"comparison uses validated controls");await settle()
    var disabled: Dictionary=await capture(lab.effect);report["off_vs_wall09"]=comparison(baseline["color"],disabled["color"])
    check(report["off_vs_wall09"]["max"]<.000001 and report["off_vs_wall09"]["iou"]==1.,"both source improvements OFF preserve WALL09")
    var proof: Dictionary=lab.effect._source_packets["proof"];var improved: bool=true
    for lod in proof["coverage"]:
        improved=improved and lod["distinct_instance_selections"]==96
        for i in range(4):improved=improved and lod["selected_first_four_instances"][i]["distance_p95_m"]<lod["baseline_first_four_instances"][i]["distance_p95_m"]*.9
    check(improved,"same source budget reduces p95 spatial gaps at all LODs and preserves 96 seeded selections")
    var uploads: int=lab.effect.asset_uploads;var geometry: int=lab.effect.geometry_rebuilds;var bank_sha: String=lab.effect.catalog["sha256"]
    lab.command({"op":"set_values","values":{"surface_continuity":true}});await settle();var continuity: Dictionary=await capture(lab.effect)
    check(lab.effect.geometry_rebuilds>geometry and lab.effect.asset_uploads==uploads,"changing source selection rebuilds geometry without bank upload")
    check(continuity["sample_invocations"]==disabled["sample_invocations"] and continuity["instances"]==97 and lab.effect.catalog["sha256"]==bank_sha,"same work, source records and instance count")
    report["continuity_vs_legacy"]=comparison(disabled["color"],continuity["color"]);save_source(continuity,"continuity")
    geometry=lab.effect.geometry_rebuilds
    lab.command({"op":"set_values","values":{"world_contacts":true}});await settle();var world: Dictionary=await capture(lab.effect)
    check(lab.effect.geometry_rebuilds==geometry and lab.effect.asset_uploads==uploads,"3D shadow toggle reuses source geometry and bank")
    var alpha_error: float=0.;var color_change: float=0.
    for i in range(0,world["color"].size(),4):
        alpha_error=maxf(alpha_error,absf(world["color"][i+3]-continuity["color"][i+3]))
        for k in range(3):color_change=maxf(color_change,absf(world["color"][i+k]-continuity["color"][i+k]))
    check(alpha_error==0. and color_change>.001 and finite_image(world),"world visibility affects light and preserves exact coverage")
    report["world_vs_screen"]={"alpha_error":alpha_error,"max_rgb_change":color_change}
    lab.command({"op":"set_values","values":{"light_azimuth":43.,"fill_azimuth":-40.}});await settle();var cached: Dictionary=await capture(lab.effect)
    lab.effect.force_geometry_rebuild();await settle();var cold: Dictionary=await capture(lab.effect)
    report["cached_vs_cold"]=comparison(cached["color"],cold["color"])
    check(report["cached_vs_cold"]["max"]<.0001 and report["cached_vs_cold"]["iou"]==1.,"persistent winner flags and source shadows match cold rebuild")
    geometry=lab.effect.geometry_rebuilds;var resolves: int=lab.effect.lighting_resolves;var solves: int=lab.transport.frame_count
    await settle(12);check(lab.effect.geometry_rebuilds==geometry and lab.effect.lighting_resolves==resolves and lab.transport.frame_count==solves,"idle source visibility remains cached")
    lab.command({"op":"set_values","values":{"exposure":1.7}});await settle()
    check(lab.effect.lighting_resolves==resolves and lab.transport.frame_count==solves,"exposure only resolves output")
    lab.command({"op":"set_values","values":{"quality_2x":true,"camera_yaw":60.}});await settle();var angled: Dictionary=await capture(lab.effect)
    check(angled["internal_size"]==1440 and finite_image(angled) and lab.effect.asset_uploads==uploads,"angled camera and resize keep real source residency")
    save_source(angled,"angled")
    var twin=load("res://lie_wall10_android_lab.tscn").instantiate();root.add_child(twin);await settle(16);var shared: Dictionary=await capture(twin.effect)
    check(twin.effect.asset_uploads==0 and twin.effect.visibility_uploads==0 and shared["cache"]["source_surface"]["shared_visibility"]["references"]==2,"two cameras share one source bank and one immutable BLAS upload")
    twin.queue_free();await settle()
    lab.command({"op":"set_values","values":{"quality_2x":false,"camera_yaw":12.,"lighting_preset":"warm_raking","light_azimuth":-62.,"fill_power":.2,"exposure":2.}});await settle();var warm: Dictionary=await capture(lab.effect);save_source(warm,"warm")
    check(warm["cache"]["source_surface"]["shared_visibility"]["references"]==1,"releasing a camera retains the other lease")
    check(lab.agent_snapshot()["collider_count"]==1 and lab.agent_snapshot()["metrics"]["visible_source_meshes"]==0,"one invisible collider and no source mesh draws")
    check(warm["passes"]["passes"].has("world_visibility") and warm["passes"]["context"]["world_contacts"],"actual GPU world-visibility timestamp and configuration")
    lab.command({"op":"set_values","values":{"world_contacts":false,"surface_continuity":false}});await settle();var before: Dictionary=await capture(lab.effect);save_source(before,"warm-before")
    report.merge({"checks":checks,"failed":failed,"device":warm["device"],"source_bank_sha256":bank_sha,"cache":warm["cache"],"passes":warm["passes"],"profile":warm["profile"],"coverage_proof":proof["coverage"],"appearance_requested_bytes":warm["allocation_bytes"],"transport_requested_bytes":lab.transport.allocation_bytes,"physical_android_tested":false})
    var file:=FileAccess.open("res://wall10-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    lab.queue_free();await settle();print("WALL10 ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
