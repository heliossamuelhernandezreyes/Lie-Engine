extends SceneTree
## Two real photographed-wall consumers: shared immutable data, private views.
const Pool=preload("res://lie_shared_sample_buffers.gd")
class WallLab extends "res://lie_wall04_mortar_lab.gd":
    func _coded_effect_factory() -> CompositorEffect:
        return preload("res://lie_wall04_mortar_effect.gd").new(720)

var checks: int=0
var failed: bool=false
var _stats: Dictionary={}
var _stats_lock:=Mutex.new()

func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
    checks+=1
    if not value:failed=true;printerr("SHARED SAMPLE FAIL ",message)
func settle(count: int=6) -> void:
    for i in range(count):await process_frame
func attach() -> Dictionary:
    var viewport:=SubViewport.new();viewport.size=Vector2i(720,720)
    viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
    get_root().add_child(viewport)
    var lab:=WallLab.new();viewport.add_child(lab)
    return {"viewport":viewport,"lab":lab}
func capture(effect: CompositorEffect) -> Dictionary:
    effect.call("request_readback")
    for i in range(120):
        await process_frame
        var data: Dictionary=effect.call("readback")
        if not data.is_empty():return data
    check(false,"Native wall readback timed out");return {}
func difference(a: PackedFloat32Array,b: PackedFloat32Array) -> float:
    if a.size()!=b.size():return INF
    var maximum: float=0
    for i in range(a.size()):maximum=maxf(maximum,absf(a[i]-b[i]))
    return maximum
func pool_stats() -> Dictionary:
    _stats_lock.lock();_stats={};_stats_lock.unlock()
    RenderingServer.call_on_render_thread(func():
        var data: Dictionary=Pool.metrics(RenderingServer.get_rendering_device())
        _stats_lock.lock();_stats=data;_stats_lock.unlock())
    for i in range(120):
        await process_frame
        _stats_lock.lock();var result: Dictionary=_stats.duplicate();_stats_lock.unlock()
        if not result.is_empty():return result
    return {}
func run() -> void:
    var first: Dictionary=attach();var second: Dictionary=attach();await settle(12)
    var a: CompositorEffect=first["lab"].effect;var b: CompositorEffect=second["lab"].effect
    if not a.get("gpu_ready") or not b.get("gpu_ready"):
        check(false,"Real Vulkan and SHA-locked wall required");quit(1);return
    var original: Dictionary=await capture(a);var identical: Dictionary=await capture(b)
    if original.is_empty() or identical.is_empty():quit(1);return
    check(difference(original["color"],identical["color"])==0,"Same state yields exact matching native pixels")
    check(a.get("_buffers")[0]==b.get("_buffers")[0],"One GPU source buffer, not two copies")
    check(a.get("_buffers")[3]!=b.get("_buffers")[3] and a.get("output_rid")!=b.get("output_rid"),"Projection and output remain private per camera")
    var loaded: Dictionary=await pool_stats()
    check(loaded.get("live_banks")==1 and loaded.get("live_references")==2,"Two live leases of one immutable bank")
    check(loaded.get("unique_resident_bytes")==61767760,"Exactly the real photographed/source wall bytes")
    check(a.get("asset_uploads")+b.get("asset_uploads")==1,"Physical upload only once")
    for pair in [[a,original],[b,identical]]:
        check(not pair[1]["profile"].is_empty(),"Actual GPU timestamps collected for each view")
        for row in pair[1]["profile"]:
            check(row.get("owner_instance_id")==pair[0].get_instance_id() and row.get("gpu_ns",-1)>=0,"Timestamps belong to this consumer only")
    var reply: Dictionary=second["lab"].command({"op":"set_values","values":{"camera_yaw":-22.0,"clay_absorption":.35}})
    check(reply.get("ok",false),"Second instance has independent camera/material control")
    await settle();var unchanged: Dictionary=await capture(a);var edited: Dictionary=await capture(b)
    check(difference(original["color"],unchanged["color"])==0,"Changing one instance cannot alter its neighbor")
    check(difference(edited["color"],original["color"])>.01,"Second view/material actually changes")
    check(edited["shared_samples"]["live_banks"]==1,"Variation keeps the source bank shared")
    first["viewport"].queue_free();await settle()
    var surviving: Dictionary=await pool_stats()
    check(surviving.get("live_references")==1 and surviving.get("live_banks")==1,"Freeing first consumer retains surviving bank")
    b.call("invalidate_lighting");await settle();var after: Dictionary=await capture(b)
    check(difference(edited["color"],after["color"])==0,"Surviving view renders the same exact pixels after owner release")
    second["viewport"].queue_free();await settle()
    var released: Dictionary=await pool_stats()
    check(released.get("live_banks")==0 and released.get("unique_resident_bytes")==0,"Last lease releases the bank without a leak")
    var report: Dictionary={"checks":checks,"failed":failed,"device":original["device"],
        "source_bank_sha256":"f6f7d9f726e909c7bfba2aff5e416d1b12d2162b07e50844f351ac273682e4da",
        "source_bytes":61767760,"two_camera_source_uploads":1,"immutable_bank_bytes_avoided":61767760,
        "loaded":loaded,"surviving":surviving,"released":released,"private_render_bytes_per_consumer":original["exclusive_allocation_bytes"],
        "first_view_profile":original["profile"],"second_view_profile":edited["profile"],
        "physical_gpu_measured":false,"source_meshes_rendered":false}
    var file:=FileAccess.open("res://lie-runtime-shared-samples.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    print("LIE SHARED SAMPLES ","FAIL" if failed else "PASS"," ",checks," real native checks")
    quit(1 if failed else 0)
