extends SceneTree
var checks: int=0
var failed: bool=false
func check(value: bool,label: String) -> void:
    checks+=1
    if not value:failed=true;printerr("MATERIAL COMMAND FAIL ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var lab=load("res://lie_wall12_android_lab.tscn").instantiate();root.add_child(lab);await process_frame
    check(lab.effect.capture_loaded,"source identity accepted")
    check(lab.effect.material_response and lab.effect.bounded_raster and lab.effect.normal_filtering,"shipping defaults")
    var revision: int=lab.revision
    for values in [{"material_response":1,"fill_power":1.},{"bounded_raster":"yes"},{"normal_filtering":0}]:check(not lab.command({"op":"set_values","values":values})["ok"] and lab.revision==revision,"invalid transaction atomic")
    check(lab.command({"op":"set_values","values":{"material_response":false,"bounded_raster":false,"normal_filtering":false}})["ok"],"validated switches")
    check(not lab.effect.material_response and not lab.effect.bounded_raster and not lab.effect.normal_filtering,"one effective path")
    var snapshot: Dictionary=lab.agent_snapshot()
    check(snapshot["control_contract"]["booleans"].has("material_response") and snapshot["control_contract"]["booleans"].has("bounded_raster") and snapshot["control_contract"]["appearance"]["requires_surface_detail"],"discovery documents effective controls")
    lab.queue_free();await process_frame;print("MATERIAL COMMAND ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
