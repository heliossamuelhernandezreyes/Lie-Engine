extends SceneTree
var checks: int=0
var failed: bool=false
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("KERNEL COMMAND FAIL ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var lab=load("res://lie_wall17_android_lab.tscn").instantiate();root.add_child(lab);await process_frame
    check(lab.effect.capture_loaded,"verified source loaded")
    var original: Dictionary=lab.state.duplicate(true);var revision: int=lab.revision
    for bad in [1,true,"invalid"]:check(not lab.command({"op":"set_values","values":{"kernel_mode":bad,"light_power":2.}})["ok"] and lab.state==original and lab.revision==revision,"mode transaction rejects invalid type/value atomically")
    for mode in lab.KERNEL_MODES:check(lab.command({"op":"set_values","values":{"kernel_mode":mode}})["ok"] and lab.effect.kernel_mode==mode,"mode accepted "+mode)
    check(not lab.command({"op":"compare_kernels","quick":1})["ok"],"quick strictly boolean")
    check(not lab.command({"op":"compare_kernels","extra":true})["ok"],"comparison unknown fields rejected")
    var backup: Dictionary=lab.state.duplicate(true)
    check(lab.command({"op":"compare_kernels","quick":true})["ok"],"comparison starts")
    check(not lab.command({"op":"set_values","values":{"light_power":2.}})["ok"],"comparison locks external mutation")
    check(not lab.command({"op":"compare_kernels"})["ok"],"comparison cannot overlap")
    lab.command({"op":"benchmark_cancel"})
    for i in range(24):await process_frame
    check(not lab.benchmark_busy and lab.state==backup and lab._comparison_report.get("restored",false) and lab._comparison_report.get("cancelled",false),"cancel restores exact state")
    var report: Dictionary=lab._build_report();var portable: Dictionary=lab._portable_report(report)
    check(report["app_version"]=="1.4.0-stage-kernels" and portable["cache"].has("kernels"),"version and kernel resources exported")
    check(JSON.stringify(portable).to_utf8_buffer().size()<16384,"compact report after cancellation")
    check(lab.agent_snapshot()["control_contract"]["kernel_modes"].size()==3,"kernel comparison discoverable")
    lab.queue_free();await process_frame;print("KERNEL COMMAND ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
