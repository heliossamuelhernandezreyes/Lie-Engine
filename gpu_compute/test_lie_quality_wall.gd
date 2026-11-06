extends SceneTree
var checks: int=0
var failed: bool=false
var metrics: Dictionary={}
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
    checks+=1;print("QUALITY WALL CHECK ",checks," ",label," ",ok)
    if not ok:failed=true;printerr("QUALITY WALL FAIL ",label)
func settle(count: int=10) -> void:
    for i in range(count):await process_frame
func capture(effect: CompositorEffect) -> Dictionary:
    effect.request_readback()
    for i in range(180):
        await process_frame
        var data: Dictionary=effect.readback()
        if not data.is_empty():return data
    check(false,"readback timeout");return {}
func difference(a: PackedFloat32Array,b: PackedFloat32Array) -> float:
    if a.size()!=b.size():return INF
    var error: float=0.
    for i in range(a.size()):error=maxf(error,absf(a[i]-b[i]))
    return error
func save(data: Dictionary,name: String) -> void:
    var image:=Image.create_from_data(data.output_size,data.output_size,false,Image.FORMAT_RGBAF,data.color.to_byte_array())
    image.convert(Image.FORMAT_RGBA8);image.save_png("res://quality-wall-"+name+".png")
func run() -> void:
    var lab=load("res://lie_quality_lab.tscn").instantiate();root.add_child(lab);await settle(24)
    check(lab.transport.gpu_ready and lab.effect.gpu_ready and lab.effect.direct_renderer!=null,"real common field and fine surface initialize")
    if lab.effect.direct_renderer==null or not lab.transport.gpu_ready:
        printerr(lab.transport.failure," / ",lab.effect.direct_failure);lab.queue_free();await settle();quit(1);return
    check(lab.effect.effective_direct_backend=="views","captured view path active without fallback")
    check(lab.effect.catalog.sha256=="ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340","attributed bank unchanged")
    var base: Dictionary=await capture(lab.effect);save(base,"open")
    var counter: Dictionary=lab.effect.cache_metrics().direct_surface
    var field_serial: int=lab.transport.frame_count;await settle(12)
    check(lab.transport.frame_count==field_serial,"idle field remains resident")
    var q: Dictionary={"angular_sectors":1,"area_budget":false}
    check(lab.command({"op":"field_policy","options":q}).ok,"old transport representation selectable")
    await settle()
    q={"angular_sectors":6,"area_budget":true}
    check(lab.command({"op":"field_policy","options":q}).ok,"improved transport restored")
    await settle()
    var back: Dictionary=await capture(lab.effect)
    metrics["policy_round_trip_max"]=difference(base.color,back.color)
    check(metrics.policy_round_trip_max<.0001,"policy round trip restores actual image")
    check(lab.effect.cache_metrics().direct_surface.primary_builds==counter.primary_builds,"policy edit retains reconstructed surface")
    # Full enclosing light-only occluder is a deterministic visibility test;
    # this asserts no residual direct OR indirect light, not visible geometry.
    check(lab.command({"op":"light_occluders","boxes":[[[-10000.,-10000.,-10000.],[10000.,10000.,10000.]]],"expected_revision":0,"new_revision":1}).ok,"dynamic visibility publication accepted")
    await settle();var dark: Dictionary=await capture(lab.effect);var peak: float=0.
    for i in range(0,dark.color.size(),4):
        for c in range(3):peak=maxf(peak,dark.color[i+c])
    metrics["occluded_peak"]=peak;check(peak<1e-6,"shared blocker removes direct and indirect light")
    var revision: int=lab.revision;field_serial=lab.transport.frame_count
    check(not lab.command({"op":"light_occluders","boxes":[],"expected_revision":0,"new_revision":2}).ok and lab.revision==revision,"stale visibility edit rejected atomically")
    await settle();check(lab.transport.frame_count==field_serial,"rejected visibility edit preserves cache")
    check(lab.command({"op":"light_occluders","boxes":[],"expected_revision":1,"new_revision":2}).ok,"dynamic visibility restoration accepted")
    await settle();back=await capture(lab.effect);save(back,"restored")
    metrics["visibility_round_trip_max"]=difference(base.color,back.color)
    check(metrics.visibility_round_trip_max<.0001,"dynamic restore returns exact scene lighting")
    check(lab.effect.cache_metrics().direct_surface.primary_builds==counter.primary_builds and lab.effect.cache_metrics().direct_surface.shadow_builds==counter.shadow_builds,"analytic blocker update retains static camera and shadow resources")
    lab.effect.force_geometry_rebuild();await settle();var cold: Dictionary=await capture(lab.effect)
    metrics["cached_vs_cold_max"]=difference(back.color,cold.color)
    check(metrics.cached_vs_cold_max<.0001,"cached and forced-cold appearance agree")
    check(lab.command({"op":"set_values","values":{"key_enabled":false,"fill_enabled":false}}).ok,"sources disabled through original API")
    await settle();dark=await capture(lab.effect);peak=0.
    for i in range(0,dark.color.size(),4):
        for c in range(3):peak=maxf(peak,dark.color[i+c])
    check(peak<1e-6,"source removal leaves no cached ambient")
    metrics.merge({"checks":checks,"failed":failed,"device":cold.device,"physical_android_tested":false,"transport_bytes":lab.transport.allocation_bytes,"quality":lab.transport.optical_metrics(),"appearance":cold.cache})
    var file:=FileAccess.open("res://quality-wall-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(metrics,"  ",true,true));file.close()
    lab.queue_free();await settle();print("QUALITY WALL ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
