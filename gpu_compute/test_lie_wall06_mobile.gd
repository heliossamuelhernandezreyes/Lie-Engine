extends SceneTree
var checks: int=0
var failed: bool=false
var report: Dictionary={}
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
    checks+=1;print("WALL06 CHECK ",checks," ",label," ",value)
    if not value:failed=true;printerr("WALL06 FAIL ",label)
func settle(count: int=8) -> void:
    for i in range(count):await process_frame
func capture(effect: CompositorEffect) -> Dictionary:
    effect.call("request_readback")
    for i in range(180):
        await process_frame
        var data: Dictionary=effect.call("readback")
        if not data.is_empty():return data
    check(false,"Readback timeout");return {}
func comparison(a: PackedFloat32Array,b: PackedFloat32Array) -> Dictionary:
    if a.size()!=b.size():return {"max":INF,"mae":INF,"iou":0}
    var worst: float=0;var error: float=0;var intersection: int=0;var union: int=0
    for i in range(0,a.size(),4):
        var aa: bool=a[i+3]>.01;var bb: bool=b[i+3]>.01
        if aa and bb:intersection+=1
        if aa or bb:union+=1
        for k in range(3):var d: float=absf(a[i+k]-b[i+k]);worst=maxf(worst,d);error+=d
    return {"max":worst,"mae":error/float(a.size()/4*3),"iou":float(intersection)/maxf(union,1)}
func save(data: Dictionary,name: String) -> void:
    var image:=Image.create_from_data(data["output_size"],data["output_size"],false,Image.FORMAT_RGBAF,data["color"].to_byte_array())
    image.convert(Image.FORMAT_RGBA8);image.save_png("res://wall06-"+name+".png")
func dark(data: Dictionary) -> int:
    var rgb: PackedFloat32Array=data["color"];var n: int=0
    for i in range(0,rgb.size(),4):
        if rgb[i+3]>.95 and maxf(rgb[i],maxf(rgb[i+1],rgb[i+2]))<.025:n+=1
    return n
func run() -> void:
    var old=load("res://lie_wall05_android_lab.tscn").instantiate();root.add_child(old);await settle(12)
    check(old.effect.gpu_ready and old.transport.gpu_ready,"Real WALL04 baseline ready")
    if not old.effect.gpu_ready:quit(1);return
    old.command({"op":"set_values","values":{"light_azimuth":-23.}});await settle()
    old.command({"op":"set_values","values":{"light_azimuth":-24.}});await settle()
    old.command({"op":"set_values","values":{"quality_2x":true}});await settle()
    var baseline: Dictionary=await capture(old.effect);save(baseline,"baseline");old.queue_free();await settle()
    report["baseline_profile"]=baseline["profile"]
    var lab=load("res://lie_wall06_android_lab.tscn").instantiate();root.add_child(lab);await settle(12)
    check(lab.effect.gpu_ready and lab.transport.gpu_ready,"Shared compositor and sparse optical transport ready")
    if not lab.effect.gpu_ready or not lab.transport.gpu_ready:printerr(lab.effect.failure," / ",lab.transport.failure);quit(1);return
    check(lab.command({"op":"set_values","values":{"quality_2x":true,"optical_codes":false,"scan_shadows":true}})["ok"],"Historical comparison through command")
    await settle();var same: Dictionary=await capture(lab.effect);save(same,"shared-legacy")
    var match: Dictionary=comparison(baseline["color"],same["color"]);report["oriented_vs_wall05"]=match
    check(match["iou"]>.5 and match["mae"]<.2,"Oriented scan renders comparable wall extent")
    check(lab.agent_snapshot()["collider_count"]==1 and lab.agent_snapshot()["metrics"]["visible_source_meshes"]==0,"One invisible envelope, no source mesh draws")
    check(same["instances"]==97 and same["cache"]["brick_master_count"]==1,"96 true brick instances reference one source master")
    var revision: int=lab.revision
    check(not lab.command({"op":"set_values","values":{"optical_codes":3,"light_power":2}})["ok"] and lab.revision==revision,"Invalid optical transaction is atomic")
    check(not lab.command({"op":"set_values","values":{"master":"brick_wall","light_power":2}})["ok"] and lab.revision==revision,"Internal source IDs cannot become an unsupported public scene")
    check(lab.agent_snapshot()["control_contract"]["masters"]==["real_scan_wall"] and lab.agent_snapshot()["control_contract"]["booleans"].has("optical_codes"),"Discovery advertises the actual wall controls")
    var gc: int=lab.effect.geometry_rebuilds;var light: int=lab.effect.lighting_resolves;var output: int=lab.effect.output_resolves
    await settle(20);check(lab.effect.geometry_rebuilds==gc and lab.effect.output_resolves==output,"Idle image stays cached")
    lab.command({"op":"set_values","values":{"exposure":1.7}});await settle()
    check(lab.effect.geometry_rebuilds==gc and lab.effect.lighting_resolves==light and lab.effect.output_resolves>output,"Exposure only resolves the final output")
    lab.command({"op":"set_values","values":{"light_azimuth":33.}});await settle()
    var cached: Dictionary=await capture(lab.effect)
    check(lab.effect.geometry_rebuilds==gc and lab.effect.recovery_reuses>0,"Moving light reuses projection, raster and recovery")
    check(cached["recovered_pixels"]>0 and cached["recovery_overflow"]==0,"Real photographic hole coefficient cache fits")
    lab.effect.force_geometry_rebuild();await settle();var cold: Dictionary=await capture(lab.effect)
    var error: Dictionary=comparison(cached["color"],cold["color"]);report["cached_vs_cold"]=error
    check(error["max"]<.0001 and error["iou"]==1.,"Cached light equals a full geometry rebuild")
    gc=lab.effect.geometry_rebuilds
    lab.command({"op":"set_values","values":{"clay_absorption":.35}});await settle()
    check(lab.effect.geometry_rebuilds==gc and lab.effect.asset_uploads==1,"Absorption changes no source/geometry upload")
    lab.command({"op":"set_values","values":{"camera_yaw":-22.}});await settle()
    check(lab.effect.geometry_rebuilds>gc,"Changing camera rebuilds the true depth")
    lab.command({"op":"set_values","values":{"camera_yaw":12.,"light_azimuth":-24.,"clay_absorption":0.,"exposure":2.,"scan_shadows":true}});await settle()
    var clipped: Dictionary=await capture(lab.effect);save(clipped,"scan-shadows")
    report["black_opaque_pixels"]={"baseline":dark(baseline),"scan_caps":dark(clipped)}
    check(dark(clipped)<dark(baseline),"Rigid orientation and mortar reduce black bands")
    gc=lab.effect.geometry_rebuilds
    lab.command({"op":"set_values","values":{"optical_codes":true}});await settle()
    var angular: Dictionary=await capture(lab.effect);save(angular,"optical")
    check(lab.effect.geometry_rebuilds==gc and lab.transport.optical_metrics()["directional_codes"],"Directional sparse codes reach the actual wall without geometry rebuild")
    lab.transport.request_readback();await settle();var codes: Dictionary=lab.transport.readback()
    var total:=Vector3.ZERO;var flux: PackedFloat32Array=codes["flux"]
    var finite: bool=true
    for i in range(0,flux.size(),4):
        finite=finite and is_finite(flux[i]) and is_finite(flux[i+1]) and is_finite(flux[i+2]) and flux[i]>=0 and flux[i+1]>=0 and flux[i+2]>=0
        total+=Vector3(flux[i],flux[i+1],flux[i+2])
    check(finite and flux.size()==872*4,"All 872 optical fluxes finite and nonnegative")
    var oracle: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/wall06-neutral-reference.json"))
    var max_error: float=0
    for i in range(872):
        for k in range(3):max_error=maxf(max_error,absf(flux[i*4+k]-float(oracle["flux"][i][k])))
    report["optical_gpu_cpu_max_error"]=max_error
    report["optical_reference_generations"]=oracle["generation_totals_rgb"]
    check(max_error<.00001,"Full scene optical transport matches independent float64")
    # Direct plus two received generations <= three times direct lamp power.
    var power: Array=lab.light_model["lights"][0]["power_rgb"]
    check(total.x<=3.*power[0]+.001 and total.y<=3.*power[1]+.001 and total.z<=3.*power[2]+.001,"Three frontier generations respect the lamp energy bound")
    gc=lab.effect.geometry_rebuilds
    lab.command({"op":"set_values","values":{"energy_radius":true}});await settle()
    var bounded: Dictionary=await capture(lab.effect)
    check(lab.light_model["secondary_radii"]["mode"]=="irradiance" and lab.effect.geometry_rebuilds==gc and not bounded.is_empty(),"Effective-radius policy reaches the sparse optical scene and preserves geometry")
    lab.command({"op":"set_values","values":{"energy_radius":false}});await settle()
    var range_restored: Dictionary=await capture(lab.effect)
    check(comparison(angular["color"],range_restored["color"])["max"]<.0001,"Removing the cutoff restores the same optical image")
    lab.command({"op":"set_values","values":{"quality_2x":false}});await settle()
    var balanced: Dictionary=await capture(lab.effect);save(balanced,"balanced")
    check(balanced["internal_size"]==1080 and balanced["output_size"]==720 and balanced["asset_uploads"]==1,"Balanced internal resolution preserves output and bank RID")
    report.merge({"checks":checks,"failed":failed,"device":balanced["device"],"cache":balanced["cache"],"allocation_bytes":balanced["allocation_bytes"],"source_bank_sha256":lab.effect.catalog["sha256"],"physical_android_tested":false,"optical":lab.transport.optical_metrics(),"received_total_rgb":[total.x,total.y,total.z],"profile":balanced["profile"],"cache_events":balanced["cache_events"]})
    var file:=FileAccess.open("res://wall06-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    lab.queue_free();await settle();print("WALL06 ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
