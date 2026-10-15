extends SceneTree
var checks: int=0
var failed: bool=false
func check(value: bool,label: String) -> void:
    checks+=1
    if not value:failed=true;printerr("SOURCE COMMAND FAIL ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var lab=load("res://lie_wall10_android_lab.tscn").instantiate();root.add_child(lab);await process_frame
    check(lab.effect.capture_loaded,"source topology and SHA validation")
    check(lab.state["surface_continuity"] and lab.state["world_contacts"],"source improvements initially enabled")
    var revision: int=lab.revision
    for values in [{"world_contacts":1,"fill_power":1.},{"surface_continuity":"yes"}]:check(not lab.command({"op":"set_values","values":values})["ok"] and lab.revision==revision,"invalid transaction atomic")
    check(lab.command({"op":"set_values","values":{"world_contacts":false,"surface_continuity":false}})["ok"],"validated comparison switches")
    check(not lab.effect.world_contacts and not lab.effect.surface_continuity,"same effect path")
    var snapshot: Dictionary=lab.agent_snapshot()
    check(snapshot["control_contract"]["booleans"].has("world_contacts") and snapshot["control_contract"]["booleans"].has("surface_continuity"),"agent discovers both switches")
    lab.queue_free();await process_frame;print("SOURCE COMMAND ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
