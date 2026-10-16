extends SceneTree
var checks: int=0
var failed: bool=false
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("STREAM COMMAND FAIL ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var lab=load("res://lie_wall19_android_lab.tscn").instantiate();root.add_child(lab);await process_frame
    check(not lab.state["visibility_stream"],"safe original path is default")
    check(lab.effect.capture_loaded and not lab.effect._stream_document.is_empty(),"verified immutable page contract")
    var original: Dictionary=lab.state.duplicate(true);var revision: int=lab.revision
    for value in [1,"yes",null]:check(not lab.command({"op":"set_values","values":{"visibility_stream":value,"light_power":2.}})["ok"] and lab.state==original and lab.revision==revision,"invalid page option atomic")
    check(lab.command({"op":"set_values","values":{"visibility_stream":false}})["ok"] and not lab.effect.visibility_stream,"reference path selectable")
    check(lab.command({"op":"set_values","values":{"visibility_stream":true}})["ok"] and lab.effect.visibility_stream,"addressed path selectable")
    check(lab.agent_snapshot()["control_contract"]["booleans"].has("visibility_stream"),"agent discovers addressed path")
    var backup: Dictionary=lab.state.duplicate(true)
    check(lab.command({"op":"compare_kernels","quick":true})["ok"],"page comparison accepted")
    check(not lab.command({"op":"set_values","values":{"visibility_stream":false}})["ok"],"comparison locks external mutation")
    lab.command({"op":"benchmark_cancel"})
    for i in range(24):await process_frame
    check(not lab.benchmark_busy and lab.state==backup and lab._comparison_report.get("restored",false) and lab._comparison_report.get("cancelled",false),"cancel restores kernel, page and scene options")
    var report: Dictionary=lab._build_report();var portable: Dictionary=lab._portable_report(report)
    check(report["app_version"]=="1.6.0-visibility-stream" and portable["cache"].has("visibility_stream"),"page resources and app version copied")
    check(portable["kernel_comparison"]["scene"]==backup and JSON.stringify(portable).to_utf8_buffer().size()<16384,"paired scene retained in compact copy")
    lab.queue_free();await process_frame;print("STREAM COMMAND ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
