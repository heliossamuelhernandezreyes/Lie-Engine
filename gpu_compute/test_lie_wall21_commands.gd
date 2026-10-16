extends SceneTree
var checks: int=0
var failed: bool=false
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("GPU DIAGNOSTICS COMMAND FAIL ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var lab=load("res://lie_wall21_android_lab.tscn").instantiate();root.add_child(lab);await process_frame
    check(not lab.state["compact_shadows"],"safe original path is default")
    check(lab.effect.capture_loaded and not lab.effect._compact_document.is_empty(),"verified immutable bounds contract")
    var probe: Dictionary=lab.command({"op":"gpu_probe"})
    check(probe["ok"] and probe["hardware"].get("native_extension",false),"native extension loaded even without supported GPU")
    check(not lab.command({"op":"gpu_probe","extra":true})["ok"],"probe rejects unknown fields")
    var original: Dictionary=lab.state.duplicate(true);var revision: int=lab.revision
    for value in [1,"yes",null]:check(not lab.command({"op":"set_values","values":{"compact_shadows":value,"light_power":2.}})["ok"] and lab.state==original and lab.revision==revision,"invalid bounds option atomic")
    check(lab.command({"op":"set_values","values":{"compact_shadows":false}})["ok"] and not lab.effect.compact_shadows,"reference path selectable")
    check(lab.command({"op":"set_values","values":{"compact_shadows":true}})["ok"] and lab.effect.compact_shadows,"refitted path selectable")
    check(lab.agent_snapshot()["control_contract"]["booleans"].has("compact_shadows"),"agent discovers refitted path")
    var backup: Dictionary=lab.state.duplicate(true)
    check(lab.command({"op":"compare_kernels","quick":true})["ok"],"bounds comparison accepted")
    check(not lab.command({"op":"set_values","values":{"compact_shadows":false}})["ok"],"comparison locks external mutation")
    check(not lab.command({"op":"gpu_probe"})["ok"],"hardware probe cannot interfere with timed comparison")
    lab.command({"op":"benchmark_cancel"})
    for i in range(24):await process_frame
    check(not lab.benchmark_busy and lab.state==backup and lab._comparison_report.get("restored",false) and lab._comparison_report.get("cancelled",false),"cancel restores kernel, bounds and scene options")
    var report: Dictionary=lab._build_report();var portable: Dictionary=lab._portable_report(report)
    check(report["app_version"]=="1.8.0-gpu-diagnostics" and portable["cache"].has("compact_shadows"),"bounds resources and app version copied")
    check(portable["kernel_comparison"]["scene"]==backup and JSON.stringify(portable).to_utf8_buffer().size()<32768,"paired scene retained in compact copy")
    lab.queue_free();await process_frame;print("GPU DIAGNOSTICS COMMAND ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
