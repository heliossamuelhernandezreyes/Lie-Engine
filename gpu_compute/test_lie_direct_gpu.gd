extends "res://test_lie_wall12_mobile.gd"
func run() -> void:
    var lab = load("res://lie_direct_lab.tscn").instantiate(); root.add_child(lab); await settle(24)
    check(lab.effect.gpu_ready and lab.transport.gpu_ready,"shared reference and transport ready")
    if not lab.effect.gpu_ready: printerr(lab.effect.failure); quit(1); return
    check(lab.effect.effective_direct_backend=="surface" and lab.effect.direct_renderer!=null,"actual native layered path ready")
    if lab.effect.direct_renderer==null: printerr(lab.effect.direct_failure); lab.queue_free(); await settle(); quit(1); return
    var native: Dictionary = await capture(lab.effect); save_material(native,"direct-default")
    var geometry: PackedFloat32Array = native["native_surface"]["surface_world"]
    var finite: bool = true; var hits: int = 0; var bad_ids: int = 0
    for i in range(0,geometry.size(),4):
        for c in range(4): finite = finite and is_finite(geometry[i+c])
        if geometry[i+3]>.5:
            hits+=1
            if geometry[i+3]>872.5: bad_ids+=1
    check(finite and hits>10000 and bad_ids==0,"real finite surface hits bind authored node IDs")
    var quality: Array = []
    for yaw in [12.,-71.4,80.,160.]:
        lab.command({"op":"set_values","values":{"direct_backend":"reference","camera_yaw":yaw}}); await settle()
        var reference: Dictionary = await capture(lab.effect); save_material(reference,"direct-reference-"+str(yaw))
        lab.command({"op":"set_values","values":{"direct_backend":"surface"}}); await settle()
        var actual: Dictionary = await capture(lab.effect); save_material(actual,"direct-native-"+str(yaw))
        var q: Dictionary = comparison(reference["color"],actual["color"]); quality.append({"yaw":yaw,"quality":q})
        print("DIRECT QUALITY ",yaw," ",q)
        check(q["iou"]>.95,"coverage compared with real source at "+str(yaw))
        check(actual["internal_size"]==reference["internal_size"] and actual["output_size"]==720,"identical resolution comparison")
    for pose in [{"camera_yaw":-39.5088,"camera_elevation":-7.2227,"distance_factor":1.},{"camera_yaw":-71.4,"camera_elevation":3.6678,"distance_factor":.6},{"camera_yaw":35.,"camera_elevation":70.,"distance_factor":.6}]:
        var values: Dictionary = pose.duplicate(); values["direct_backend"] = "reference"
        lab.command({"op":"set_values","values":values}); await settle()
        var reference: Dictionary = await capture(lab.effect)
        lab.command({"op":"set_values","values":{"direct_backend":"surface"}}); await settle()
        var actual: Dictionary = await capture(lab.effect); var q: Dictionary = comparison(reference["color"],actual["color"])
        quality.append({"pose":pose,"quality":q}); print("DIRECT QUALITY POSE ",pose," ",q)
        save_material(reference,"direct-pose-reference-"+str(quality.size())); save_material(actual,"direct-pose-native-"+str(quality.size()))
        check(q["iou"]>.95,"near/phone/top coverage compared with attributed source")
    lab.command({"op":"set_values","values":{"camera_elevation":9.,"distance_factor":1.}}); await settle()
    lab.command({"op":"set_values","values":{"camera_yaw":12.}}); await settle()
    var before: Dictionary = lab.effect.cache_metrics()["direct_surface"]
    lab.command({"op":"set_values","values":{"camera_yaw":18.}}); await settle()
    var camera: Dictionary = lab.effect.cache_metrics()["direct_surface"]
    check(camera["primary_builds"]>before["primary_builds"] and camera["shadow_builds"]==before["shadow_builds"] and camera["node_builds"]==before["node_builds"],"camera rebuilds primary only; shadow/node fields reused")
    lab.command({"op":"set_values","values":{"light_power":1.3}}); await settle()
    var power: Dictionary = lab.effect.cache_metrics()["direct_surface"]
    check(power["primary_builds"]==camera["primary_builds"] and power["shadow_builds"]==camera["shadow_builds"] and power["node_builds"]>camera["node_builds"],"power rebuilds node response without primary/shadow search")
    lab.command({"op":"set_values","values":{"light_azimuth":-58.}}); await settle()
    var moved: Dictionary = lab.effect.cache_metrics()["direct_surface"]
    check(moved["primary_builds"]==power["primary_builds"] and moved["shadow_builds"]>power["shadow_builds"],"moving light rebuilds light maps without primary")
    check(moved["shadow_light_builds"]==power["shadow_light_builds"]+1,"moving key light rebuilds only its six views")
    lab.command({"op":"set_values","values":{"key_enabled":true,"fill_enabled":false}}); await settle()
    var key: PackedFloat32Array = linear(await capture(lab.effect))
    lab.command({"op":"set_values","values":{"key_enabled":false,"fill_enabled":true}}); await settle()
    var fill: PackedFloat32Array = linear(await capture(lab.effect))
    lab.command({"op":"set_values","values":{"key_enabled":true,"fill_enabled":true}}); await settle()
    var both_image: Dictionary = await capture(lab.effect); var both: PackedFloat32Array = linear(both_image); var sum_error: float = 0.
    for i in range(0,both.size(),4):
        if both[i+3]<.99: continue
        for c in range(3): sum_error=maxf(sum_error,absf(key[i+c]+fill[i+c]-both[i+c]))
    check(sum_error<.0002,"independent sources sum once in linear radiance")
    report["source_superposition_linear_max"] = sum_error
    lab.command({"op":"set_values","values":{"key_enabled":false,"fill_enabled":false}}); await settle()
    var black: Dictionary = await capture(lab.effect); var peak: float = 0.
    for i in range(0,black["color"].size(),4):
        for c in range(3): peak=maxf(peak,black["color"][i+c])
    check(peak<.00001,"no invented light with both sources disabled")
    lab.command({"op":"set_values","values":{"key_enabled":true,"fill_enabled":true}}); await settle()
    var restored: Dictionary = await capture(lab.effect); save_material(restored,"direct-restored")
    same(both_image,restored,"source disable/re-enable restores exact native image")
    lab.effect.force_geometry_rebuild(); await settle()
    same(restored,await capture(lab.effect),"cached native lighting equals fresh primary and shadow maps")
    var frames: int = lab.effect.frame_count; await settle(12)
    check(lab.effect.frame_count==frames,"idle image cache")
    var backup: Dictionary = lab.state.duplicate(true)
    if OS.get_environment("LIE_DIRECT_COMPARE")=="1":
        var quick: bool = OS.get_environment("LIE_DIRECT_FULL") != "1"
        check(lab.command({"op":"compare_kernels","quick":quick})["ok"],"paired comparison accepted")
        for i in range(30000):
            await process_frame
            if not lab.benchmark_busy: break
        check(not lab.benchmark_busy and lab._comparison_report.get("error","missing")=="" and lab.state==backup,"comparison completes and restores")
        check(lab._comparison_report.get("summary",[]).size()==9,"all nine mode/change groups timed")
        for group in lab._comparison_report.get("summary",[]): check(group["gpu"]["samples"]==(3 if quick else 12),"all outer GPU intervals retained")
        await settle()
        same(restored,await capture(lab.effect),"rotated benchmark restores the actual native image")
    var portable: Dictionary = lab._portable_report(lab._build_report())
    check(portable["cache"]["direct_surface"]["effective_backend"]=="surface","portable report identifies actual renderer")
    report.merge({"checks":checks,"failed":failed,"quality":quality,"hits":hits,"cache":moved,"physical_android_tested":false,"comparison":lab._comparison_report})
    var file:=FileAccess.open("res://direct-surface-native.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"  ",true,true)); file.close()
    lab.queue_free(); await settle(); print("DIRECT SURFACE ",checks," ","FAIL" if failed else "PASS"); quit(1 if failed else 0)
