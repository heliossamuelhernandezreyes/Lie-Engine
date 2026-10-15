extends "res://test_lie_wall07_mobile.gd"
## Same accepted photographic bank; real source-separated transport and cache.
func run() -> void:
    var old=load("res://lie_wall07_android_lab.tscn").instantiate();root.add_child(old);await settle(14)
    check(old.effect.gpu_ready and old.transport.gpu_ready,"WALL07 baseline ready")
    if not old.effect.gpu_ready or not old.transport.gpu_ready:quit(1);return
    var baseline: Dictionary=await capture(old.effect);old.queue_free();await settle()
    var lab=load("res://lie_wall08_android_lab.tscn").instantiate();root.add_child(lab);await settle(16)
    check(lab.effect.gpu_ready and lab.transport.gpu_ready,"Common source-light field and photographic compositor ready")
    if not lab.effect.gpu_ready or not lab.transport.gpu_ready:printerr(lab.effect.failure," / ",lab.transport.failure);quit(1);return
    lab.command({"op":"set_values","values":{"fill_enabled":false}});await settle()
    var single: Dictionary=await capture(lab.effect);var same: Dictionary=comparison(baseline["color"],single["color"])
    report["single_light_vs_wall07"]=same
    check(same["max"]<.0001 and same["iou"]==1.,"Single-light image preserves WALL07")
    check(lab.agent_snapshot()["collider_count"]==1 and lab.agent_snapshot()["metrics"]["visible_source_meshes"]==0,"One invisible envelope and no source mesh draws")
    check(single["instances"]==97 and single["asset_uploads"]==1,"96 virtual bricks share one upload")
    var left: Dictionary=await capture(lab.transport)
    check(lab.command({"op":"set_values","values":{"fill_enabled":true,"key_enabled":false}})["ok"],"Isolate fill through a valid source switch");await settle()
    var right: Dictionary=await capture(lab.transport)
    check(lab.command({"op":"set_values","values":{"key_enabled":true}})["ok"],"Reenable key through the same validated control");await settle()
    var both: Dictionary=await capture(lab.transport);var image: Dictionary=await capture(lab.effect)
    var sum_error: float=0.;var max_error: float=0.;var finite: bool=true;var total:=Vector3.ZERO
    var oracle: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/wall08-field-reference.json"))
    for i in range(872):
        for k in range(3):
            var at: int=i*4+k;var actual: float=both["flux"][at]
            sum_error=maxf(sum_error,absf(actual-left["flux"][at]-right["flux"][at]))
            max_error=maxf(max_error,absf(actual-float(oracle["flux"][i][k])))
            finite=finite and is_finite(actual) and actual>=0
        total+=Vector3(both["flux"][i*4],both["flux"][i*4+1],both["flux"][i*4+2])
    check(finite and both["flux"].size()==872*4,"Every field code finite and nonnegative")
    check(sum_error<.00001,"Actual wall GPU obeys source superposition")
    check(max_error<.00001,"Full two-light wall matches independent float64")
    report["source_superposition_max_error"]=sum_error;report["wall_gpu_cpu_max_error"]=max_error
    report["reference_generations"]=oracle["generation_totals_rgb"]
    check(both["frontier_channels"].size()==872*2*4,"Distinct resident frontier for each source light")
    var lamps: Array=lab.light_model["lights"];var limit:=Vector3.ZERO
    for light in lamps:var p: Array=light["power_rgb"];limit+=3.*Vector3(p[0],p[1],p[2])
    check(total.x<=limit.x+.001 and total.y<=limit.y+.001 and total.z<=limit.z+.001,"Cumulative direct plus two bounces respects lamp budget")
    var gc: int=lab.effect.geometry_rebuilds;var uploads: int=lab.effect.asset_uploads
    lab.command({"op":"set_values","values":{"fill_azimuth":-55.}});await settle()
    var cached: Dictionary=await capture(lab.effect)
    check(lab.effect.geometry_rebuilds==gc and lab.effect.asset_uploads==uploads,"Second light moves without geometry or bank upload")
    lab.effect.force_geometry_rebuild();await settle();var cold: Dictionary=await capture(lab.effect)
    var cached_error: Dictionary=comparison(cached["color"],cold["color"]);report["cached_vs_cold"]=cached_error
    check(cached_error["max"]<.0001 and cached_error["iou"]==1.,"Two-light cached reconstruction equals full geometry rebuild")
    var solves: int=lab.transport.frame_count;gc=lab.effect.geometry_rebuilds;var out: int=lab.effect.output_resolves
    await settle(16);check(lab.transport.frame_count==solves,"Idle transport remains cached")
    lab.command({"op":"set_values","values":{"exposure":1.7}});await settle()
    check(lab.transport.frame_count==solves and lab.effect.geometry_rebuilds==gc and lab.effect.output_resolves>out,"Exposure does not recalculate light or geometry")
    var revision: int=lab.revision
    check(not lab.command({"op":"set_values","values":{"fill_power":NAN,"light_power":2.}})["ok"] and lab.revision==revision,"Invalid multi-light transaction is atomic")
    check(lab.light_registry.snapshot()["ids"]==["key","fill"],"Stable emitter IDs survive control changes")
    check(lab.agent_snapshot()["control_contract"]["limits"].has("fill_power"),"Agent discovers real multi-light limits")
    lab.command({"op":"set_values","values":{"fill_azimuth":55.,"exposure":2.,"energy_radius":true}});await settle()
    check(lab.effect.geometry_rebuilds==gc and lab.light_model.has("secondary_radii"),"Radius cutoff is a light-only update")
    lab.command({"op":"set_values","values":{"energy_radius":false}});await settle()
    var restored: Dictionary=await capture(lab.effect)
    check(comparison(image["color"],restored["color"])["max"]<.0001,"Removing cutoff restores two-light image")
    lab.command({"op":"set_values","values":{"separate_lights":false}});await settle()
    var merged: Dictionary=await capture(lab.effect);report["merged_vs_separate"]=comparison(image["color"],merged["color"])
    check(lab.effect.geometry_rebuilds==gc and not lab.transport.optical_metrics()["separate_lights"],"Legacy directional comparison preserves source geometry")
    lab.command({"op":"set_values","values":{"separate_lights":true}});await settle()
    var again: Dictionary=await capture(lab.effect)
    check(comparison(image["color"],again["color"])["max"]<.0001,"Returning to source separation restores image")
    var three: Dictionary=lab.light_model.duplicate(true);three["lights"].append({"position":[0.,1.,1.],"radius":6.,"power_rgb":[0.,0.,0.]})
    check(lab.transport.configure(three),"Source count can grow within resident capacity")
    lab.effect.invalidate_lighting();await settle();var grown: Dictionary=await capture(lab.effect)
    check(lab.transport.optical_metrics()["lights"]==3 and comparison(image["color"],grown["color"])["max"]<.0001 and lab.effect.geometry_rebuilds==gc,"Adding a zero-power source preserves image and geometry")
    check(lab.transport.configure(lab.light_model),"Source count can shrink without reallocating geometry")
    lab.effect.invalidate_lighting();await settle()
    lab.command({"op":"set_values","values":{"lighting_preset":"warm_raking","light_azimuth":-62.,"fill_power":.2}});await settle()
    var warm: Dictionary=await capture(lab.effect)
    var png:=Image.create_from_data(warm["output_size"],warm["output_size"],false,Image.FORMAT_RGBAF,warm["color"].to_byte_array());png.convert(Image.FORMAT_RGBA8);png.save_png("res://wall08-warm.png")
    report.merge({"checks":checks,"failed":failed,"device":warm["device"],"cache":warm["cache"],"appearance_allocation_bytes":warm["allocation_bytes"],"transport_allocation_bytes":lab.transport.allocation_bytes,"source_bank_sha256":lab.effect.catalog["sha256"],"physical_android_tested":false,"optical":lab.transport.optical_metrics(),"profile":warm["profile"],"transport_profile":lab.transport.transport_metrics(),"registry":lab.light_registry.snapshot()})
    var file:=FileAccess.open("res://wall08-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    lab.queue_free();await settle();print("WALL08 ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
