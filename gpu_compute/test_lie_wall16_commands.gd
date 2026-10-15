extends SceneTree
const Plan=preload("res://lie_surface_query_plan.gd")
var checks: int=0
var failed: bool=false
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("QUERY COMMAND FAIL ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var plan=Plan.new();var a:=PackedByteArray([1,2]);var b:=PackedByteArray([3]);var c:=PackedByteArray([4])
    check(plan.prepare("bank-domain",a,b,c),"first world derivation")
    check(not plan.prepare("bank-domain",a,b,c),"same world ignores camera and light updates")
    check(plan.prepare("other-bank",a,b,c),"master domain invalidates")
    check(plan.prepare("other-bank",PackedByteArray([1]),b,c),"instance assembly invalidates")
    check(plan.prepare("other-bank",PackedByteArray([1]),PackedByteArray([2,3]),c),"packet boundaries remain unambiguous")
    check(plan.prepare("other-bank",a,b,PackedByteArray([5])),"LOD schedule invalidates")
    plan.invalidate();check(plan.prepare("other-bank",a,b,PackedByteArray([5])),"explicit invalidation")
    var lab=load("res://lie_wall16_android_lab.tscn").instantiate();root.add_child(lab);await process_frame
    check(lab.effect.capture_loaded,"immutable bank and source scene loaded")
    var revision: int=lab.revision
    for values in [{"surface_queries":1,"light_power":2.},{"occlusion_witnesses":"yes"}]:check(not lab.command({"op":"set_values","values":values})["ok"] and lab.revision==revision,"new booleans validate atomically")
    check(lab.command({"op":"set_values","values":{"surface_queries":false,"occlusion_witnesses":false}})["ok"],"comparison options accepted")
    var report: Dictionary=lab.command({"op":"diagnostic_report"})["report"]
    check(report["app_version"]=="1.3.0-surface-queries" and not report["optimization_controls"]["surface_queries"],"version and controls exported")
    check(lab._portable_report(report)["cache"].has("surface_queries"),"compact report retains architecture metrics")
    check(lab.agent_snapshot()["control_contract"]["booleans"].has("occlusion_witnesses"),"agent discovers both query controls")
    lab.queue_free();await process_frame;print("QUERY COMMAND ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
