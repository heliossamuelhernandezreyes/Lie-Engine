extends SceneTree
var checks: int = 0
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok: failed = true; printerr("DIRECT COMMAND FAIL ",label)
func run() -> void:
    var lab = load("res://lie_direct_views_lab.tscn").instantiate(); root.add_child(lab); await process_frame
    check(lab.effect.capture_loaded,"attributed bank")
    for mode in ["reference","regions","views","views_fast","native"]:
        check(lab.command({"op":"set_values","values":{"direct_backend":mode}})["ok"],"existing validated command selects "+mode)
        check(lab.state["direct_backend"]==mode and lab.effect.direct_backend==mode,"control and consumer agree")
    var backup: Dictionary = lab.state.duplicate(true); var revision: int = lab.revision
    for value in ["bad",2,null]:
        check(not lab.command({"op":"set_values","values":{"direct_backend":value,"light_power":2.}})["ok"],"invalid backend rejected atomically")
        check(lab.state==backup and lab.revision==revision,"failed command does not mutate")
    check(lab.command({"op":"compare_kernels","quick":true})["ok"],"comparison uses existing endpoint")
    check(not lab.command({"op":"set_values","values":{"light_power":2.}})["ok"],"comparison transaction locks external edits")
    lab.command({"op":"benchmark_cancel"})
    for i in range(60): await process_frame
    check(not lab.benchmark_busy and lab.state==backup,"cancel restores exact state")
    check(lab.command({"op":"compare_kernels","quick":true})["ok"],"second comparison accepted")
    for i in range(3): await process_frame
    lab.command({"op":"benchmark_cancel"})
    for i in range(60): await process_frame
    check(not lab.benchmark_busy and lab.state==backup,"mid-event cancellation restores without timing a failed event")
    lab.queue_free(); await process_frame
    print("DIRECT COMMAND ",checks," ","FAIL" if failed else "PASS"); quit(1 if failed else 0)
