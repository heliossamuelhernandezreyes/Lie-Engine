extends SceneTree
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("SCREEN COMMAND FAIL ",label)
func run() -> void:
    var lab=load("res://lie_wall22_android_lab.tscn").instantiate();root.add_child(lab);await process_frame
    check(lab.effect.capture_loaded and not lab.state["screen_tiles"],"verified bank and reference default")
    var original: Dictionary=lab.state.duplicate(true);var revision: int=lab.revision
    for value in [1,"yes",null]:check(not lab.command({"op":"set_values","values":{"screen_tiles":value,"light_power":2.}})["ok"] and lab.state==original and lab.revision==revision,"invalid tile transaction atomic")
    check(lab.command({"op":"set_values","values":{"screen_tiles":true}})["ok"] and lab.effect.screen_tiles,"screen path selectable")
    check(lab.command({"op":"set_values","values":{"screen_tiles":false}})["ok"] and not lab.effect.screen_tiles,"reference selectable")
    check(lab.agent_snapshot()["control_contract"]["booleans"].has("screen_tiles") and lab.TILE_MODES.size()==4,"agent discovers four isolated modes")
    for mode in lab.TILE_MODES:
        var values: Dictionary=lab._mode_state(original,mode)
        check(not values["compact_shadows"] and not values["visibility_stream"] and values["kernel_mode"]=="split","each comparison holds unrelated paths constant")
    check(lab.command({"op":"compare_kernels","quick":true})["ok"],"matrix comparison accepted")
    check(not lab.command({"op":"set_values","values":{"screen_tiles":true}})["ok"],"external mutation locked")
    lab.command({"op":"benchmark_cancel"})
    for i in range(24):await process_frame
    check(not lab.benchmark_busy and lab.state==original and lab._comparison_report.get("restored",false) and lab._comparison_report.get("cancelled",false),"cancel restores four-mode options and scene")
    var report: Dictionary=lab._build_report();var portable: Dictionary=lab._portable_report(report)
    check(report["app_version"]=="1.9.0-screen-tiles" and portable["cache"].has("screen_tiles"),"new version and resource scope copied")
    check(portable["kernel_comparison"]["scene"]==original and JSON.stringify(portable).to_utf8_buffer().size()<32768,"copy retains exact paired scene")
    lab.queue_free();await process_frame;print("SCREEN COMMAND ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
