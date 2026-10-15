extends "res://test_lie_wall07_mobile.gd"
var events: Dictionary={}
func save_identity(data: Dictionary,label: String) -> void:
    var image:=Image.create_from_data(data["output_size"],data["output_size"],false,Image.FORMAT_RGBAF,data["color"].to_byte_array());image.convert(Image.FORMAT_RGBA8);image.save_png("res://wall11-"+label+".png")
func take(lab,label: String) -> Dictionary:
    var data: Dictionary=await capture(lab.effect)
    check(data.has("color") and data.has("visibility_work"),label+" real GPU readback")
    if not data.has_all(["color","visibility_work"]):printerr(data.keys()," / ",lab.effect.failure);quit(1);return {}
    events[label]={"frame":data["frames"],"visibility":data["visibility_work"],"work":data["sample_invocations"],"internal_size":data["internal_size"]};return data
func total(values: Array) -> int:
    var sum: int=0
    for v in values:sum+=v
    return sum
func queries(data: Dictionary) -> int:return total(data["visibility_work"]["queries"])
func hits(data: Dictionary) -> int:return total(data["visibility_work"]["hits"])
func same(a: Dictionary,b: Dictionary,label: String) -> void:
    var error: Dictionary=comparison(a["color"],b["color"]);report[label]=error
    check(error["max"]<.0001 and error["iou"]==1.,label)
func run() -> void:
    var old=load("res://lie_wall10_android_lab.tscn").instantiate();root.add_child(old);await settle(16)
    check(old.effect.gpu_ready,"accepted WALL10 baseline ready")
    if not old.effect.gpu_ready:printerr(old.effect.failure);quit(1);return
    var baseline: Dictionary=await capture(old.effect);old.queue_free();await settle()
    var lab=load("res://lie_wall11_android_lab.tscn").instantiate();root.add_child(lab);await settle(16)
    check(lab.effect.gpu_ready and lab.transport.gpu_ready,"persistent source identity and light ready")
    if not lab.effect.gpu_ready:printerr(lab.effect.failure);quit(1);return
    lab.command({"op":"set_values","values":{"persistent_visibility":false,"block_access":false,"visibility_diagnostics":true}});await settle()
    var disabled: Dictionary=await take(lab,"off");same(baseline,disabled,"both new switches OFF preserve WALL10")
    save_identity(disabled,"off")
    var identity: Dictionary=disabled["sample_identity"]
    check(identity["rid_matches"] and identity["first_offset"]==0 and identity["last_offset"]==(int(lab.effect.catalog["sample_count"])-1)*80 and identity["stale_rejected"] and identity["outside_rejected"],"direct resident source address and generation guards")
    lab.command({"op":"set_values","values":{"block_access":true}});await settle();var blocks: Dictionary=await take(lab,"blocks")
    same(disabled,blocks,"direct source blocks preserve exact reconstruction")
    check(blocks["sample_invocations"]==disabled["sample_invocations"] and blocks["cache"]["persistent_visibility"]["padding"]<97*64,"same genuine work and bounded schedule padding")
    lab.command({"op":"set_values","values":{"persistent_visibility":true}});lab.effect.clear_visibility_cache();await settle();var cold: Dictionary=await take(lab,"cold")
    same(blocks,cold,"persistent cache preserves uncached visibility")
    save_identity(cold,"cold")
    check(queries(cold)>0 and hits(cold)==0,"explicit cold solve queries the source")
    lab.effect.force_geometry_rebuild();await settle();var warm: Dictionary=await take(lab,"warm")
    same(cold,warm,"reprojecting known source IDs reuses exact shadows")
    check(queries(warm)==0 and hits(warm)>0 and warm["visibility_work"]["dirty_lights"]==0,"same camera rebuild performs no 3D queries")
    lab.command({"op":"set_values","values":{"light_power":1.35,"fill_power":.48}});await settle();var power: Dictionary=await take(lab,"radiometry")
    check(queries(power)==0 and hits(power)>0 and power["visibility_work"]["dirty_lights"]==0,"changing radiometry keeps geometric visibility")
    check(comparison(power["color"],warm["color"])["max"]>.001,"changed power actually updates lighting")
    lab.command({"op":"set_values","values":{"light_azimuth":43.}});await settle();var moved: Dictionary=await take(lab,"moved_key")
    check(moved["visibility_work"]["queries"][0]>0 and moved["visibility_work"]["queries"][1]==0 and moved["visibility_work"]["hits"][1]>0 and moved["visibility_work"]["dirty_lights"]==1,"moving key invalidates its source only")
    lab.effect.clear_visibility_cache();await settle();var moved_cold: Dictionary=await take(lab,"moved_cold");same(moved,moved_cold,"per-source invalidation matches full cold query")
    lab.command({"op":"set_values","values":{"camera_yaw":60.}});await settle();var angle: Dictionary=await take(lab,"angle")
    save_identity(angle,"angle")
    check(hits(angle)>0,"new camera reuses already known 3D sample identities")
    lab.effect.force_geometry_rebuild();await settle();var angle_warm: Dictionary=await take(lab,"angle_warm")
    check(queries(angle_warm)==0 and hits(angle_warm)>0,"second angled view has no new visibility queries");same(angle,angle_warm,"angled cache equals full projection rebuild")
    lab.command({"op":"set_values","values":{"camera_yaw":12.}});await settle();var back: Dictionary=await take(lab,"camera_return")
    check(queries(back)==0,"returning camera retains old source results");same(moved_cold,back,"camera roundtrip preserves the source image")
    lab.command({"op":"set_values","values":{"fill_enabled":false}});lab.effect.clear_visibility_cache();await settle();var off: Dictionary=await take(lab,"fill_off")
    check(off["visibility_work"]["queries"][0]>0 and off["visibility_work"]["queries"][1]==0 and off["visibility_work"]["zero_power_skips"][1]>0,"zero-power source does not acquire false cache validity")
    lab.command({"op":"set_values","values":{"fill_enabled":true}});await settle();var on: Dictionary=await take(lab,"fill_on")
    check(on["visibility_work"]["queries"][0]==0 and on["visibility_work"]["queries"][1]>0,"reenabled source queries only its missing channel");same(back,on,"disable/enable preserves the physical result")
    lab.command({"op":"set_values","values":{"quality_2x":true}});await settle();var resized: Dictionary=await take(lab,"resized")
    check(resized["internal_size"]==1440 and hits(resized)>0 and lab.effect.asset_uploads==1,"resizing reuses source residency and known shadow entries")
    lab.command({"op":"set_values","values":{"quality_2x":false}});await settle();var before_twin: Dictionary=await take(lab,"before_twin")
    var view:=SubViewport.new();view.size=Vector2i(720,720);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_DISABLED;root.add_child(view)
    var twin=load("res://lie_wall11_android_lab.tscn").instantiate();view.add_child(twin)
    twin.command({"op":"set_values","values":{"light_azimuth":43.,"light_power":1.35,"fill_power":.48,"visibility_diagnostics":true}})
    view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;await settle(16);var shared: Dictionary=await take(twin,"second_view")
    check(twin.effect.asset_uploads==0 and twin.effect.visibility_uploads==0 and twin.effect.shadow_allocations==0 and shared["cache"]["persistent_visibility"]["shared"]["references"]==2,"two independent views share bank, BLAS and mutable identity cache")
    check(queries(shared)==0 and hits(shared)>0,"second camera consumes first camera shadow results");same(before_twin,shared,"shared camera matches independently lit output")
    twin.command({"op":"set_values","values":{"light_azimuth":-55.}});await settle();var different: Dictionary=await take(twin,"other_light_world")
    check(different["visibility_work"]["queries"][0]>0 and different["visibility_work"]["queries"][1]==0,"different view light configuration cannot reuse stale key shadows")
    lab.effect.force_geometry_rebuild();await settle();var coherent: Dictionary=await take(lab,"restored_light_world")
    check(coherent["visibility_work"]["queries"][0]>0 and coherent["visibility_work"]["queries"][1]==0,"GPU position keys serialize shared-cache consumers");same(before_twin,coherent,"alternating light worlds keep correct images")
    lab.command({"op":"set_values","values":{"surface_continuity":false,"persistent_visibility":false}});await settle();var legacy_uncached: Dictionary=await take(lab,"legacy_off")
    lab.command({"op":"set_values","values":{"persistent_visibility":true}});await settle();var legacy_cached: Dictionary=await take(lab,"legacy_on")
    same(legacy_uncached,legacy_cached,"reference-selection domain prevents identity aliasing")
    check(legacy_cached["cache"]["persistent_visibility"]["shared"]["domains"]==2,"different reference identities have separate cache storage")
    lab.command({"op":"set_values","values":{"surface_continuity":true}});await settle();var returned: Dictionary=await take(lab,"domain_return")
    same(before_twin,returned,"returning to shared identity domain preserves source lighting")
    view.queue_free();await settle();var retained: Dictionary=await take(lab,"retained")
    check(retained["cache"]["persistent_visibility"]["shared"]["references"]==1 and retained["cache"]["persistent_visibility"]["shared"]["domains"]==1,"consumer release preserves live source cache and frees unused domain")
    var resolves: int=lab.effect.lighting_resolves;var geometry: int=lab.effect.geometry_rebuilds;var frames: int=lab.effect.frame_count
    await settle(12);check(lab.effect.frame_count==frames,"idle does not dispatch source or visibility work")
    lab.command({"op":"set_values","values":{"exposure":1.7}});await settle()
    check(lab.effect.lighting_resolves==resolves and lab.effect.geometry_rebuilds==geometry,"exposure only resolves output")
    lab.command({"op":"set_values","values":{"visibility_diagnostics":false}});await settle();var final: Dictionary=await take(lab,"diagnostics_off")
    check(not final["visibility_work"]["instrumented"] and queries(final)==0 and hits(final)==0,"shipping mode avoids per-query diagnostic atomics")
    check(lab.agent_snapshot()["collider_count"]==1 and lab.agent_snapshot()["metrics"]["visible_source_meshes"]==0 and final["instances"]==97,"one invisible collider and authentic source instances")
    report.merge({"checks":checks,"failed":failed,"device":final["device"],"events":events,"cache":final["cache"],"passes":final["passes"],"appearance_requested_bytes":final["allocation_bytes"],"transport_requested_bytes":lab.transport.allocation_bytes,"source_bank_sha256":lab.effect.catalog["sha256"],"physical_android_tested":false})
    var file:=FileAccess.open("res://wall11-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    lab.queue_free();await settle();print("WALL11 ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
