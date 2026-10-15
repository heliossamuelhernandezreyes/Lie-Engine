extends SceneTree
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("MOBILE CONTROL FAIL ",label)
func touch(lab,index: int,position: Vector2,pressed: bool) -> void:
    var event:=InputEventScreenTouch.new();event.index=index;event.position=position;event.pressed=pressed;lab._input(event)
func drag(lab,index: int,position: Vector2) -> void:
    var event:=InputEventScreenDrag.new();event.index=index;event.position=position;lab._input(event)
func run() -> void:
    var lab=load("res://lie_wall14_android_lab.tscn").instantiate();root.add_child(lab);await process_frame
    check(lab.effect.capture_loaded,"verified source available")
    var before: Dictionary=lab.state.duplicate(true);var revision: int=lab.revision
    touch(lab,0,Vector2(400,350),true);drag(lab,0,Vector2(500,400));lab._flush_gesture();touch(lab,0,Vector2(500,400),false)
    check(lab.revision==revision+1 and lab.state["camera_yaw"]!=before["camera_yaw"] and lab.state["camera_elevation"]!=before["camera_elevation"],"one touch commits one orbit transaction")
    check(lab.controls["camera_yaw"].value==lab.state["camera_yaw"],"slider and touch share validated state")
    check(lab.state["light_azimuth"]==before["light_azimuth"] and lab.state["seed"]==before["seed"],"orbit preserves lights and deterministic asset")
    revision=lab.revision;touch(lab,0,Vector2(1050,350),true);drag(lab,0,Vector2(1100,400));lab._flush_gesture()
    check(lab.revision==revision and lab._touches.is_empty(),"panel input does not orbit wall")
    var distance: float=lab.state["distance_factor"]
    touch(lab,0,Vector2(300,350),true);touch(lab,1,Vector2(500,350),true);drag(lab,1,Vector2(700,350));lab._flush_gesture()
    check(lab.state["distance_factor"]<distance and lab.state["distance_factor"]>=.6,"two touches zoom with authored limits")
    lab._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT);check(lab._touches.is_empty(),"focus loss clears active fingers")
    lab._show_report()
    check(lab._report_dialog.visible and lab._report_text.text.contains("lie-mobile-diagnostics/1") and not lab._report_content.is_empty(),"report available without prior benchmark")
    var persisted: Variant=JSON.parse_string(FileAccess.get_file_as_string("user://lie-performance-last.json"))
    check(persisted is Dictionary and persisted["schema"]=="lie-mobile-diagnostics/1","real JSON saved and readable")
    revision=lab.revision;touch(lab,0,Vector2(400,350),true);drag(lab,0,Vector2(500,400));lab._flush_gesture();check(lab.revision==revision,"report modal blocks orbit")
    lab._report_dialog.hide()
    check(not lab.command({"op":"diagnose","extra":true})["ok"],"diagnostic protocol rejects unknown fields")
    var backup: Dictionary=lab.state.duplicate(true)
    check(lab.command({"op":"diagnose"})["ok"] and not lab.command({"op":"set_values","values":{"camera_yaw":0.}})["ok"],"diagnostic locks mutation")
    check(lab.command({"op":"diagnostic_report"})["ok"],"report inspectable during diagnostic")
    lab.command({"op":"benchmark_cancel"})
    for i in range(24):await process_frame
    check(not lab.benchmark_busy and lab.state==backup and lab._diagnostic_report.get("restored",false) and lab._diagnostic_report.get("cancelled",false),"cancellation restores exact state")
    check(lab.agent_snapshot()["touch_controls"]["changes_wall_geometry"]==false,"inspection scope explicit")
    lab.queue_free();await process_frame;print("MOBILE CONTROL ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
