extends SceneTree
var checks: int=0
var failed: bool=false
func check(value: bool,label: String) -> void:
    checks+=1
    if not value:failed=true;printerr("PERSISTENT COMMAND FAIL ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var lab=load("res://lie_wall11_android_lab.tscn").instantiate();root.add_child(lab);await process_frame
    check(lab.effect.capture_loaded,"stable identity and dispatch schedule accepted")
    check(lab.state["persistent_visibility"] and lab.state["block_access"] and not lab.state["visibility_diagnostics"],"efficient defaults")
    var revision: int=lab.revision
    for values in [{"persistent_visibility":1,"fill_power":1.},{"block_access":"yes"},{"visibility_diagnostics":0}]:check(not lab.command({"op":"set_values","values":values})["ok"] and lab.revision==revision,"invalid transaction atomic")
    check(lab.command({"op":"set_values","values":{"persistent_visibility":false,"block_access":false,"visibility_diagnostics":true}})["ok"],"validated comparison switches")
    check(not lab.effect.persistent_visibility and not lab.effect.block_access and lab.effect.visibility_diagnostics,"one effective control path")
    var snapshot: Dictionary=lab.agent_snapshot()
    check(snapshot["control_contract"]["booleans"].has("persistent_visibility") and snapshot["control_contract"]["booleans"].has("block_access"),"discovery exposes resident controls")
    var asset_id: String=lab.effect.sample_identity._assets.keys()[0];revision=lab.revision
    var address: Dictionary=lab.command({"op":"sample_address","asset_id":asset_id,"lod":0.,"sample_index":1.})
    check(address["ok"] and address["address"]["byte_offset"]==address["address"]["source_id"]*80 and lab.revision==revision,"read-only ID address resolves without scene mutation")
    for request in [{"op":"sample_address","asset_id":"missing","lod":0,"sample_index":0},{"op":"sample_address","asset_id":asset_id,"lod":0,"sample_index":.5},{"op":"sample_address","asset_id":asset_id,"lod":0,"sample_index":true},{"op":"sample_address","asset_id":asset_id,"lod":0,"sample_index":0,"path":"outside"}]:check(not lab.command(request)["ok"] and lab.revision==revision,"invalid address request cannot alias source or mutate scene")
    lab.queue_free();await process_frame;print("PERSISTENT COMMAND ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
