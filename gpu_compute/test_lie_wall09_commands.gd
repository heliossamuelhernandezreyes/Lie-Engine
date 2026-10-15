extends SceneTree
var checks: int=0
var failed: bool=false
func check(value: bool,label: String) -> void:
    checks+=1
    if not value:failed=true;printerr("SURFACE COMMAND FAIL ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var lab=load("res://lie_wall09_android_lab.tscn").instantiate();root.add_child(lab);await process_frame
    check(lab.state["contact_shadows"] and lab.state["surface_detail"],"enabled by default")
    var revision: int=lab.revision
    for values in [{"contact_shadows":1,"fill_power":1.},{"surface_detail":"yes"},{"contact_steps":3},{"contact_steps":33},{"contact_steps":12.5}]:
        check(not lab.command({"op":"set_values","values":values})["ok"] and lab.revision==revision,"invalid transaction atomic "+str(values))
    check(lab.command({"op":"set_values","values":{"contact_shadows":false,"surface_detail":false,"contact_steps":32}})["ok"],"validated comparison switches")
    check(not lab.effect.contact_shadows and not lab.effect.surface_detail and lab.effect.contact_steps==32,"same public implementation path")
    check(lab.command(JSON.parse_string('{"op":"set_values","values":{"contact_steps":12}}'))["ok"] and lab.effect.contact_steps==12,"integral JSON agent numbers accepted")
    var snapshot: Dictionary=lab.agent_snapshot()
    check(snapshot["control_contract"]["booleans"].has("contact_shadows") and snapshot["control_contract"]["limits"]["contact_steps"]==[4,32],"discoverable contact controls")
    lab.queue_free();await process_frame;print("SURFACE COMMAND ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
