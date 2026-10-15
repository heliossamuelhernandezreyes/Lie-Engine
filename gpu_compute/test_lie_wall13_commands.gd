extends SceneTree
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
    checks+=1
    if not value:failed=true;printerr("AREA COMMAND FAIL ",label)
func run() -> void:
    var lab=load("res://lie_wall13_android_lab.tscn").instantiate();root.add_child(lab);await process_frame
    check(lab.effect.capture_loaded,"verified source loaded")
    check(lab.effect.fused_shading and lab.effect.surface_filter and not lab.state["area_lights"],"shipping defaults")
    var revision: int=lab.revision
    for values in [{"fused_shading":1,"fill_power":1.},{"surface_filter":"yes"},{"area_lights":0},{"area_size":true},{"area_size":-1.},{"area_size":INF}]:check(not lab.command({"op":"set_values","values":values})["ok"] and lab.revision==revision,"invalid transaction atomic")
    check(lab.command({"op":"set_values","values":{"area_lights":true,"area_size":.5,"surface_filter":false}})["ok"],"validated area controls")
    check(lab.light_world.render_snapshot()["lights"].size()==8 and not lab.effect.surface_filter,"effective common render path")
    for request in [{"op":"benchmark","quick":1},{"op":"benchmark","extra":true},{"op":"benchmark_result","extra":true}]:check(not lab.command(request)["ok"],"benchmark protocol rejects unknown fields")
    check(lab.command({"op":"benchmark_result"})["result"].is_empty(),"result inspection is read only")
    check(lab.agent_snapshot()["control_contract"]["benchmark"]["restores_state"],"benchmark discoverable")
    lab.queue_free();await process_frame;print("AREA COMMAND ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
