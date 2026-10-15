extends "res://test_lie_wall12_mobile.gd"
func save_area(data: Dictionary,label: String) -> void:
    var image:=Image.create_from_data(data["output_size"],data["output_size"],false,Image.FORMAT_RGBAF,data["color"].to_byte_array());image.convert(Image.FORMAT_RGBA8);image.save_png("res://wall13-"+label+".png")
func run() -> void:
    var old=load("res://lie_wall12_android_lab.tscn").instantiate();root.add_child(old);await settle(16)
    check(old.effect.gpu_ready,"accepted 0.9 baseline ready")
    if not old.effect.gpu_ready:quit(1);return
    var baseline: Dictionary=await capture(old.effect);old.queue_free();await settle()
    var lab=load("res://lie_wall13_android_lab.tscn").instantiate();root.add_child(lab);await settle(16)
    check(lab.effect.gpu_ready and lab.transport.gpu_ready,"new pipeline ready")
    if not lab.effect.gpu_ready or not lab.transport.gpu_ready:printerr(lab.effect.failure," / ",lab.transport.failure);quit(1);return
    lab.command({"op":"set_values","values":{"fused_shading":false,"surface_filter":false,"visibility_diagnostics":true}});await settle()
    var separate: Dictionary=await take(lab,"separate");same(baseline,separate,"all new options OFF preserve 0.9")
    lab.command({"op":"set_values","values":{"fused_shading":true}});await settle();var fused: Dictionary=await take(lab,"fused")
    same(separate,fused,"fused base equals separate composition");check(separate["depth"]==fused["depth"],"fusion preserves depth")
    var gc: int=lab.effect.geometry_rebuilds;var builds: int=lab.effect.material_builds;var bytes: int=lab.effect.allocation_bytes
    lab.command({"op":"set_values","values":{"surface_filter":true}});await settle();var filtered: Dictionary=await take(lab,"filtered");save_area(filtered,"filtered");save_area(fused,"raw")
    var delta: Dictionary=comparison(fused["color"],filtered["color"]);report["filter_delta"]=delta
    check(delta["max"]>.0001 and delta["iou"]==1. and fused["depth"]==filtered["depth"],"filter affects material while keeping true geometry")
    check(lab.effect.geometry_rebuilds==gc and lab.effect.material_builds==builds+1,"filter builds once without reprojection")
    lab.command({"op":"set_values","values":{"fused_shading":false}});await settle();var filtered_separate: Dictionary=await take(lab,"filtered_separate");same(filtered,filtered_separate,"filtered fused/separate exact match")
    lab.command({"op":"set_values","values":{"fused_shading":true,"light_power":1.3}});await settle();var power: Dictionary=await take(lab,"power")
    check(lab.effect.geometry_rebuilds==gc and lab.effect.material_builds==builds+1 and queries(power)==0,"radiometry reuses material geometry and visibility")
    var resolves: int=lab.effect.lighting_resolves
    lab.command({"op":"set_values","values":{"exposure":1.7}});await settle();check(lab.effect.geometry_rebuilds==gc and lab.effect.lighting_resolves==resolves,"exposure only updates output")
    lab.command({"op":"set_values","values":{"exposure":1.}});await settle()
    for angle in [60.,80.]:
        lab.command({"op":"set_values","values":{"camera_yaw":angle}});await settle();var view: Dictionary=await take(lab,"view_"+str(angle))
        lab.effect.force_geometry_rebuild();await settle();var cold: Dictionary=await take(lab,"cold_"+str(angle));same(view,cold,"angle filter cache/cold "+str(angle));check(queries(cold)==0,"warm source shadows reused "+str(angle))
    lab.command({"op":"set_values","values":{"camera_yaw":12.,"lighting_preset":"warm_raking","light_azimuth":-72.,"light_power":1.2}});await settle();var point: Dictionary=await take(lab,"warm_point");save_area(point,"warm-point")
    gc=lab.effect.geometry_rebuilds;builds=lab.effect.material_builds
    lab.command({"op":"set_values","values":{"area_lights":true}});await settle();var area: Dictionary=await take(lab,"warm_area");save_area(area,"warm-area")
    check(lab.transport.optical_metrics()["lights"]==8 and lab.light_world.render_snapshot()["logical_ids"]==["key","fill"],"two logical panels share eight physical channels")
    check(lab.effect.geometry_rebuilds==gc and lab.effect.material_builds==builds,"emitter shape reuses material and geometry")
    var area_delta: Dictionary=comparison(point["color"],area["color"]);report["area_delta"]=area_delta
    check(area_delta["max"]>.001 and area_delta["iou"]==1. and point["depth"]==area["depth"],"area emitter updates real light without moving surfaces")
    lab.effect.force_geometry_rebuild();await settle();var area_rebuilt: Dictionary=await take(lab,"area_rebuilt");same(area,area_rebuilt,"area shading matches full reconstruction");check(queries(area_rebuilt)==0,"area visibility cache warm")
    lab.command({"op":"set_values","values":{"area_size":.65}});await settle();var resized_panel: Dictionary=await take(lab,"panel_size")
    check(resized_panel["visibility_work"]["dirty_lights"]==255 and queries(resized_panel)>0,"panel size invalidates eight actual source rays")
    lab.effect.clear_visibility_cache();await settle();var resized_cold: Dictionary=await take(lab,"panel_size_cold");same(resized_panel,resized_cold,"panel geometry invalidation equals full cold query")
    lab.command({"op":"set_values","values":{"fill_enabled":false}});await settle();var key: Dictionary=await take(lab,"key")
    lab.command({"op":"set_values","values":{"key_enabled":false,"fill_enabled":true}});await settle();var fill: Dictionary=await take(lab,"fill")
    lab.command({"op":"set_values","values":{"key_enabled":true}});await settle();var both: Dictionary=await take(lab,"both")
    var k: PackedFloat32Array=linear(key);var f: PackedFloat32Array=linear(fill);var b: PackedFloat32Array=linear(both);var worst: float=0.
    for i in range(0,b.size(),4):
        if b[i+3]<.99:continue
        for c in range(3):worst=maxf(worst,absf(k[i+c]+f[i+c]-b[i+c]))
    report["source_superposition_linear_max"]=worst;check(worst<.0003,"finite warm/cool sources sum in linear radiance")
    lab.command({"op":"set_values","values":{"key_enabled":false,"fill_enabled":false}});await settle();var black: Dictionary=await take(lab,"black");var energy: float=0.
    for i in range(0,black["color"].size(),4):
        for c in range(3):energy=maxf(energy,black["color"][i+c])
    check(energy<.00001,"both panels OFF emit zero")
    lab.command({"op":"set_values","values":{"key_enabled":true,"fill_enabled":true,"area_lights":false}});await settle();var returned: Dictionary=await take(lab,"point_return");same(point,returned,"logical centers and total power survive area roundtrip")
    lab.command({"op":"set_values","values":{"quality_2x":true}});await settle();var size2: Dictionary=await take(lab,"supersampled");check(size2["internal_size"]==1440 and lab.effect.asset_uploads==1,"unsigned material packet resize reuses bank")
    lab.command({"op":"set_values","values":{"quality_2x":false,"surface_filter":false,"visibility_diagnostics":false}});await settle()
    var serials: Array=[]
    for index in range(6):
        var fused_mode: bool=index%2==1;lab.command({"op":"set_values","values":{"fused_shading":fused_mode}});lab.effect.force_geometry_rebuild();await settle();serials.append({"serial":lab.effect.frame_count,"fused":fused_mode})
    lab.command({"op":"set_values","values":{"fused_shading":true,"surface_filter":true}});await settle()
    var backup: Dictionary=lab.state.duplicate(true);check(lab.command({"op":"benchmark","quick":true})["ok"],"benchmark starts through validated command")
    for i in range(2000):
        await process_frame
        if not lab.benchmark_busy:break
    var benchmark: Dictionary=lab.command({"op":"benchmark_result"})["result"];report["benchmark"]=benchmark
    check(not lab.benchmark_busy and benchmark.get("events",[]).size()==8 and benchmark.get("restored",false) and lab.state==backup and not benchmark.get("physical_android",true),"four-mode software benchmark restores exact state and labels device")
    await settle();var final: Dictionary=await take(lab,"shipping")
    check(lab.effect.asset_uploads==1 and lab.effect.allocation_bytes==bytes and final["instances"]==97 and lab.agent_snapshot()["collider_count"]==1 and lab.agent_snapshot()["metrics"]["visible_source_meshes"]==0,"same master bank memory and one invisible collider")
    var frames: int=lab.effect.frame_count;await settle(12);check(lab.effect.frame_count==frames,"idle remains cached")
    report.merge({"checks":checks,"failed":failed,"device":final["device"],"events":events,"interleaved_serials":serials,"passes":final["passes"],"cache":final["cache"],"appearance_requested_bytes":final["allocation_bytes"],"transport_requested_bytes":lab.transport.allocation_bytes,"source_bank_sha256":lab.effect.catalog["sha256"],"physical_android_tested":false})
    var file:=FileAccess.open("res://wall13-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    lab.queue_free();await settle();print("WALL13 ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
