extends "res://test_lie_wall07_mobile.gd"
func save_surface(data: Dictionary,name: String) -> void:
    var image:=Image.create_from_data(data["output_size"],data["output_size"],false,Image.FORMAT_RGBAF,data["color"].to_byte_array());image.convert(Image.FORMAT_RGBA8);image.save_png("res://wall09-"+name+".png")
func run() -> void:
    var old=load("res://lie_wall08_android_lab.tscn").instantiate();root.add_child(old);await settle(16)
    check(old.effect.gpu_ready and old.transport.gpu_ready,"accepted WALL08 baseline ready")
    if not old.effect.gpu_ready or not old.transport.gpu_ready:quit(1);return
    var baseline: Dictionary=await capture(old.effect);old.queue_free();await settle()
    var lab=load("res://lie_wall09_android_lab.tscn").instantiate();root.add_child(lab);await settle(16)
    check(lab.effect.gpu_ready and lab.transport.gpu_ready,"surface bridge and compositor ready")
    if not lab.effect.gpu_ready or not lab.transport.gpu_ready:printerr(lab.effect.failure," / ",lab.transport.failure);quit(1);return
    check(lab.command({"op":"set_values","values":{"contact_shadows":false,"surface_detail":false}})["ok"],"comparison uses validated controls");await settle()
    var disabled: Dictionary=await capture(lab.effect);report["off_vs_wall08"]=comparison(baseline["color"],disabled["color"])
    save_surface(disabled,"neutral-before")
    check(report["off_vs_wall08"]["max"]<.000001 and report["off_vs_wall08"]["iou"]==1.,"both OFF preserves accepted image")
    var geometry: int=lab.effect.geometry_rebuilds;var uploads: int=lab.effect.asset_uploads
    lab.command({"op":"set_values","values":{"contact_shadows":true}});await settle();var contacts: Dictionary=await capture(lab.effect)
    var brightening: float=0.;var alpha_error: float=0.;var darkened: int=0
    for i in range(0,contacts["color"].size(),4):
        alpha_error=maxf(alpha_error,absf(contacts["color"][i+3]-disabled["color"][i+3]))
        for k in range(3):
            var difference: float=contacts["color"][i+k]-disabled["color"][i+k];brightening=maxf(brightening,difference)
            if difference<-.001:darkened+=1
    check(brightening<.000001 and alpha_error==0.,"contact-only attenuates without changing coverage")
    report["contact_only"]={"max_brightening":brightening,"alpha_error":alpha_error,"darkened_channels":darkened}
    check(darkened>0,"contact actually affects captured geometry");save_surface(contacts,"neutral-contact-only")
    lab.command({"op":"set_values","values":{"surface_detail":true}});await settle();var detailed: Dictionary=await capture(lab.effect)
    report["detail_vs_baseline"]=comparison(disabled["color"],detailed["color"])
    check(report["detail_vs_baseline"]["max"]>.001 and report["detail_vs_baseline"]["iou"]==1.,"captured detail changes direct shading only")
    var finite: bool=true
    save_surface(detailed,"neutral-detail-contact")
    for value in detailed["color"]:finite=finite and is_finite(value) and value>=0.
    check(finite,"every final channel finite and nonnegative")
    check(lab.effect.geometry_rebuilds==geometry and lab.effect.asset_uploads==uploads,"new switches reuse geometry and immutable bank")
    lab.command({"op":"set_values","values":{"light_azimuth":43.,"fill_azimuth":-40.}});await settle();var cached: Dictionary=await capture(lab.effect)
    lab.effect.force_geometry_rebuild();await settle();var cold: Dictionary=await capture(lab.effect)
    report["cached_vs_cold"]=comparison(cached["color"],cold["color"])
    check(report["cached_vs_cold"]["max"]<.0001 and report["cached_vs_cold"]["iou"]==1.,"surface recovery cache agrees with cold rebuild")
    geometry=lab.effect.geometry_rebuilds;var solves: int=lab.transport.frame_count;var shades: int=lab.effect.lighting_resolves
    await settle(12);check(lab.effect.geometry_rebuilds==geometry and lab.transport.frame_count==solves,"idle remains cached")
    lab.command({"op":"set_values","values":{"exposure":1.7}});await settle()
    check(lab.effect.geometry_rebuilds==geometry and lab.transport.frame_count==solves and lab.effect.lighting_resolves==shades,"exposure never compounds refinement")
    lab.command({"op":"set_values","values":{"quality_2x":true}});await settle();var resized: Dictionary=await capture(lab.effect)
    check(resized["internal_size"]==1440 and resized["asset_uploads"]==uploads,"resize preserves bank and shared surface packet")
    check(lab.agent_snapshot()["collider_count"]==1 and lab.agent_snapshot()["metrics"]["visible_source_meshes"]==0 and resized["instances"]==97,"one invisible collider and 97 virtual instances")
    lab.command({"op":"set_values","values":{"quality_2x":false,"lighting_preset":"warm_raking","light_azimuth":-62.,"fill_power":.2,"exposure":2.}});await settle();var warm: Dictionary=await capture(lab.effect);save_surface(warm,"warm")
    lab.command({"op":"set_values","values":{"contact_shadows":false,"surface_detail":false}});await settle();var warm_old: Dictionary=await capture(lab.effect);save_surface(warm_old,"warm-before")
    check(warm["passes"]["available"] and warm["passes"]["passes"].has_all(["project","raster","surface_light","output"]),"asynchronous actual GPU timestamps for each pass")
    check(warm["passes"]["context"]=={"internal_size":1080,"contacts":true,"detail":true,"steps":12},"percentiles group the same resolution and options")
    report.merge({"checks":checks,"failed":failed,"device":warm["device"],"profile":warm["profile"],"passes":warm["passes"],"cache":warm["cache"],"appearance_allocation_bytes":warm["allocation_bytes"],"transport_allocation_bytes":lab.transport.allocation_bytes,"source_bank_sha256":lab.effect.catalog["sha256"],"physical_android_tested":false})
    var file:=FileAccess.open("res://wall09-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    lab.queue_free();await settle();print("WALL09 ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
