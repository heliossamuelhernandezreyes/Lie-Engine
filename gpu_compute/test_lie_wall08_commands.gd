extends SceneTree
## Real UI/agent command path, exercised without a GPU before native images.
var checks: int=0
var failed: bool=false
func check(value: bool,label: String) -> void:
    checks+=1
    if not value:failed=true;printerr("FIELD COMMAND FAIL ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var lab=load("res://lie_wall08_android_lab.tscn").instantiate();root.add_child(lab)
    await process_frame
    check(lab.light_registry.snapshot()["ids"]==["key","fill"],"two stable scene emitters")
    var original: Array=lab.light_model["lights"].duplicate(true)
    check(original[0]["power_rgb"][0]>0 and original[1]["power_rgb"][0]>0,"both lights initially contribute")
    check(lab.command({"op":"set_values","values":{"key_enabled":false}})["ok"],"valid key switch")
    check(lab.light_model["lights"][0]["power_rgb"]==[0.,0.,0.] and lab.light_model["lights"][1]["power_rgb"]==original[1]["power_rgb"],"fill-only code preserves its color and energy")
    check(lab.command({"op":"set_values","values":{"fill_enabled":false}})["ok"],"valid fill switch")
    check(lab.light_model["lights"][0]["power_rgb"]==[0.,0.,0.] and lab.light_model["lights"][1]["power_rgb"]==[0.,0.,0.],"both sources can be off")
    check(lab.command({"op":"set_values","values":{"key_enabled":true}})["ok"],"key can reenable")
    check(lab.light_model["lights"][0]["power_rgb"]==original[0]["power_rgb"],"key recovers original energy after zero code")
    check(lab.command({"op":"set_values","values":{"fill_enabled":true}})["ok"],"fill can reenable")
    check(lab.light_model["lights"]==original,"both codes restore exactly")
    var revision: int=lab.revision
    check(not lab.command({"op":"set_values","values":{"light_power":0.,"fill_enabled":false}})["ok"] and lab.revision==revision and lab.state["fill_enabled"],"legacy invalid intensity cannot partially change a source switch")
    check(not lab.command({"op":"set_values","values":{"key_enabled":2,"fill_power":1.}})["ok"] and lab.revision==revision,"source switch type rejection is atomic")
    var snapshot: Dictionary=lab.agent_snapshot()
    check(snapshot["control_contract"]["booleans"].has("key_enabled") and snapshot["control_contract"]["limits"]["fill_power"]==[0.,2.],"all actual controls discoverable")
    lab.queue_free();await process_frame
    print("FIELD COMMAND ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
