extends "res://test_lie_wall12_mobile.gd"

func validate_lifetime(lab, mode: String) -> void:
    lab.command({"op":"set_values","values":{"direct_backend":mode,"camera_yaw":12.,"camera_elevation":9.,"distance_factor":1.,"light_azimuth":-72.,"light_power":1.2,"key_enabled":true,"fill_enabled":true}}); await settle()
    var before: Dictionary = lab.effect.cache_metrics()["direct_surface"]
    lab.command({"op":"set_values","values":{"camera_yaw":18.}}); await settle()
    var camera: Dictionary = lab.effect.cache_metrics()["direct_surface"]
    check(camera["primary_builds"]==before["primary_builds"]+1 and camera["shadow_builds"]==before["shadow_builds"] and camera["node_builds"]==before["node_builds"],mode+" camera reuses light maps and node response")
    lab.command({"op":"set_values","values":{"light_power":1.3}}); await settle()
    var power: Dictionary = lab.effect.cache_metrics()["direct_surface"]
    check(power["primary_builds"]==camera["primary_builds"] and power["shadow_builds"]==camera["shadow_builds"] and power["node_builds"]>camera["node_builds"],mode+" scalar power reuses geometry and shadow maps")
    lab.command({"op":"set_values","values":{"light_azimuth":-58.}}); await settle()
    var moved: Dictionary = lab.effect.cache_metrics()["direct_surface"]
    check(moved["primary_builds"]==power["primary_builds"] and moved["shadow_light_builds"]==power["shadow_light_builds"]+1,mode+" only moved light rebuilds six views")
    lab.command({"op":"set_values","values":{"fill_enabled":false}}); await settle()
    var key: PackedFloat32Array = linear(await capture(lab.effect))
    lab.command({"op":"set_values","values":{"key_enabled":false,"fill_enabled":true}}); await settle()
    var fill: PackedFloat32Array = linear(await capture(lab.effect))
    lab.command({"op":"set_values","values":{"key_enabled":true}}); await settle()
    var both_image: Dictionary = await capture(lab.effect); var both: PackedFloat32Array = linear(both_image); var error: float = 0.
    for i in range(0,both.size(),4):
        if both[i+3]<.99: continue
        for c in range(3): error=maxf(error,absf(key[i+c]+fill[i+c]-both[i+c]))
    check(error<.0002,mode+" independent sources sum once in linear radiance")
    lab.command({"op":"set_values","values":{"key_enabled":false,"fill_enabled":false}}); await settle()
    var black: Dictionary = await capture(lab.effect); var peak: float = 0.
    for i in range(0,black["color"].size(),4):
        for c in range(3): peak=maxf(peak,black["color"][i+c])
    check(peak<.00001,mode+" source removal leaves no invented ambient")
    lab.command({"op":"set_values","values":{"key_enabled":true,"fill_enabled":true}}); await settle()
    same(both_image,await capture(lab.effect),mode+" source round-trip restores image")
    lab.effect.force_geometry_rebuild(); await settle()
    same(both_image,await capture(lab.effect),mode+" cached image equals fresh primary and maps")
    var frames: int = lab.effect.frame_count; await settle(12)
    check(lab.effect.frame_count==frames,mode+" idle emits no extra solve")

func run() -> void:
    var lab = load("res://lie_direct_lab.tscn").instantiate(); root.add_child(lab); await settle(24)
    check(lab.effect.gpu_ready and lab.effect.direct_renderer!=null,"real Vulkan alternate consumers initialize")
    if lab.effect.direct_renderer==null: printerr(lab.effect.direct_failure); quit(1); return
    var quality: Array = []
    var poses: Array = [{"camera_yaw":12.,"camera_elevation":9.,"distance_factor":1.},{"camera_yaw":-71.4,"camera_elevation":3.6678,"distance_factor":.6},{"camera_yaw":-63.7914,"camera_elevation":-.0774,"distance_factor":.61}]
    if OS.get_environment("LIE_ACCESS_FULL")=="1": poses.append_array([{"camera_yaw":80.,"camera_elevation":9.,"distance_factor":1.},{"camera_yaw":160.,"camera_elevation":9.,"distance_factor":1.},{"camera_yaw":-39.5088,"camera_elevation":-7.2227,"distance_factor":1.},{"camera_yaw":35.,"camera_elevation":70.,"distance_factor":.6}])
    for index in range(poses.size()):
        var values: Dictionary = poses[index].duplicate(); values["direct_backend"] = "reference"
        lab.command({"op":"set_values","values":values}); await settle()
        var reference: Dictionary = await capture(lab.effect); save_material(reference,"access-reference-"+str(index))
        var baseline: Dictionary = {}
        for mode in ["surface","regions","envelope"]:
            lab.command({"op":"set_values","values":{"direct_backend":mode}}); await settle()
            var actual: Dictionary = await capture(lab.effect); save_material(actual,"access-"+mode+"-"+str(index))
            var q: Dictionary = comparison(reference["color"],actual["color"])
            quality.append({"pose":poses[index],"backend":mode,"reference_quality":q}); print("ACCESS QUALITY ",index," ",mode," ",q)
            check(q["iou"]>.95,mode+" silhouette against attributed source, view "+str(index))
            var world: PackedFloat32Array = actual["native_surface"]["surface_world"]; var valid: bool = true; var hits: int = 0
            for i in range(0,world.size(),4):
                for c in range(4): valid=valid and is_finite(world[i+c])
                if world[i+3]>.5: hits+=1; valid=valid and world[i+3]<872.5
            check(valid and hits>10000,mode+" finite real hits and original authored IDs")
            if mode=="surface": baseline=actual
            if mode=="regions":
                var delta: Dictionary = comparison(baseline["color"],actual["color"])
                quality[-1]["baseline_quality"] = delta; print("ACCESS REGION EQUIVALENCE ",delta)
                check(delta["iou"]>.9999 and delta["mae"]<.00001,"region skip preserves actual full lighting image")
    for mode in ["surface","regions","envelope"]: await validate_lifetime(lab,mode)
    lab.command({"op":"set_values","values":{"direct_backend":"regions","camera_yaw":-63.7914,"camera_elevation":-.0774,"distance_factor":.61}}); await settle()
    var restored: Dictionary = await capture(lab.effect); var backup: Dictionary = lab.state.duplicate(true)
    if OS.get_environment("LIE_DIRECT_COMPARE")=="1":
        var quick: bool = OS.get_environment("LIE_DIRECT_FULL")!="1"
        check(lab.command({"op":"compare_kernels","quick":quick})["ok"],"actual six-mode benchmark accepted")
        for i in range(90000):
            await process_frame
            if not lab.benchmark_busy: break
        var result: Dictionary = lab._comparison_report
        check(not lab.benchmark_busy and result.get("error","missing")=="" and lab.state==backup,"comparison completes and restores state")
        check(result.get("summary",[]).size()==18,"all 18 representation/resolution/change groups timed")
        for group in result.get("summary",[]): check(group["gpu"]["samples"]==(3 if quick else 12),"every whole GPU event retained")
        check(result.get("stage_events",[]).size()==54 and result.get("stage_summary",[]).size()==18,"separate stage diagnostic is complete")
        for group in result.get("stage_summary",[]):
            check(group["whole_instrumented_gpu"]["samples"]==3 and group["passes"].has("shading") and group["passes"].has("output"),"stage rows joined to independent outer serials")
            check(group["unattributed_gpu"].get("p50_ms",-10.)>-.01,"per-event stage sum does not double count whole interval")
        await settle(); same(restored,await capture(lab.effect),"full benchmark restores actual image after all modes/resolutions")
    var portable: Dictionary = lab._portable_report(lab._build_report())
    check(portable["cache"]["direct_surface"]["effective_backend"]=="regions","portable report identifies executable backend")
    report.merge({"checks":checks,"failed":failed,"quality":quality,"physical_android_tested":false,"cache":lab.effect.cache_metrics(),"comparison":lab._comparison_report})
    var file:=FileAccess.open("res://direct-access-native.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"  ",true,true)); file.close()
    lab.queue_free(); await settle(); print("DIRECT ACCESS ",checks," ","FAIL" if failed else "PASS"); quit(1 if failed else 0)
