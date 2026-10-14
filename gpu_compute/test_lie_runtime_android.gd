extends SceneTree
## Actual mobile renderer, true source bank, ordinary validated UI commands.
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
    checks+=1
    if not value:failed=true;printerr("ANDROID LAB FAIL ",message)
func settle(count: int=6) -> void:
    for i in range(count):await process_frame
func capture(effect: CompositorEffect) -> Dictionary:
    effect.call("request_readback")
    for i in range(120):
        await process_frame
        var data: Dictionary=effect.call("readback")
        if not data.is_empty():return data
    check(false,"Native source readback timeout");return {}
func difference(a: PackedFloat32Array,b: PackedFloat32Array) -> float:
    if a.size()!=b.size():return INF
    var result: float=0
    for i in range(a.size()):result=maxf(result,absf(a[i]-b[i]))
    return result
func run() -> void:
    var lab=load("res://lie_runtime_android_lab.tscn").instantiate();root.add_child(lab)
    await settle(12)
    check(lab.effect.gpu_ready and lab.transport.gpu_ready,"Both native compute stages run")
    if not lab.effect.gpu_ready or not lab.transport.gpu_ready:quit(1);return
    var baseline: Dictionary=await capture(lab.effect)
    if baseline.is_empty():quit(1);return
    check(baseline["output_size"]==720 and baseline["asset_uploads"]==1,"Phone preset and source bank once")
    check(lab.agent_snapshot()["collider_count"]==1 and lab.agent_snapshot()["metrics"]["visible_source_meshes"]==0,"One invisible envelope, no rendered source mesh")
    var revision: int=lab.revision
    check(not lab.command({"op":"set_values","values":{"energy_radius":1,"light_power":2}})["ok"] and lab.revision==revision,"Invalid radius UI transaction changes nothing")
    check(lab.command({"op":"set_values","values":{"energy_radius":true}})["ok"],"Energy radius uses original validated command")
    await settle();var enabled: Dictionary=await capture(lab.effect)
    check(lab.light_model["secondary_radii"]["mode"]=="irradiance" and not enabled.is_empty(),"Opt-in mode reaches real transport")
    check(lab.command({"op":"set_values","values":{"energy_radius":false}})["ok"],"Legacy comparison restored")
    await settle();var restored: Dictionary=await capture(lab.effect)
    check(difference(baseline["color"],restored["color"])==0,"Returning to baseline restores exact pixels")
    check(lab.command({"op":"set_values","values":{"camera_yaw":-22.,"clay_absorption":.35}})["ok"],"Touch-control camera/material path")
    await settle();var changed: Dictionary=await capture(lab.effect)
    check(difference(baseline["color"],changed["color"])>.01,"Real wall responds to controls")
    check(changed["asset_uploads"]==1,"Controls do not re-upload the bank")
    var file:=FileAccess.open("res://lie-runtime-android-native.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failed":failed,"device":baseline["device"],"physical_android_tested":false,"wall_bank_sha256":lab.effect.catalog["sha256"]},"  ",true,true));file.close()
    lab.queue_free();await settle()
    print("ANDROID LAB ","FAIL" if failed else "PASS"," ",checks," native mobile-renderer checks")
    quit(1 if failed else 0)
