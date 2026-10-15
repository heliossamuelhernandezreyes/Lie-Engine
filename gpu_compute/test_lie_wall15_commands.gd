extends SceneTree
var checks: int=0
var failed: bool=false
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("ACTIVE COMMAND FAIL ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var lab=load("res://lie_wall15_android_lab.tscn").instantiate();root.add_child(lab);await process_frame
    check(lab.effect.capture_loaded,"verified source loaded")
    var revision: int=lab.revision
    for values in [{"active_visibility":1,"light_power":2.},{"precomputed_ray_boxes":"yes"},{"cpu_reuse":0}]:check(not lab.command({"op":"set_values","values":values})["ok"] and revision==lab.revision,"invalid option transaction atomic")
    var builds: int=lab.instance_packets.builds;var shape: Shape3D=lab.get_node("InvisibleBrick/OnlyCollider").shape
    for values in [{"camera_yaw":20.},{"light_power":1.2},{"light_azimuth":-40.},{"exposure":1.5}]:check(lab.command({"op":"set_values","values":values})["ok"],"normal controls accepted")
    check(lab.instance_packets.builds==builds and lab.instance_packets.reuses>=4,"camera/lights reuse exact instance packets")
    check(lab.get_node("InvisibleBrick/OnlyCollider").shape==shape,"unchanged collider resource is retained")
    lab.command({"op":"set_values","values":{"distance_factor":1.4}});check(lab.instance_packets.builds==builds+1,"LOD change prepares its own packet")
    lab.command({"op":"set_values","values":{"distance_factor":1.}});check(lab.instance_packets.builds==builds+1,"LOD return reuses original packet")
    lab.command({"op":"set_values","values":{"cpu_reuse":false}});builds=lab.instance_packets.builds;lab.command({"op":"set_values","values":{"camera_yaw":21.}})
    check(lab.instance_packets.builds==builds+1,"CPU comparison switch restores uncached preparation")
    var pending: Dictionary=lab.effect._pending.duplicate(true);var inputs: Dictionary=lab.effect._configured_inputs
    var bad_params: PackedByteArray=pending["parameters"].duplicate();bad_params.encode_s32(80,int(pending["work"])+1)
    check(not lab.effect.configure(bad_params,inputs["source_instances"],inputs["source_jobs"],pending["work"]) and lab.effect._pending["parameters"]==pending["parameters"],"cached validation rejects mismatched parameter work atomically")
    var bad_jobs: PackedByteArray=inputs["source_jobs"].duplicate();bad_jobs.encode_s32(4,bad_jobs.decode_s32(4)+1)
    check(not lab.effect.configure(pending["parameters"],inputs["source_instances"],bad_jobs,pending["work"]),"changed malformed jobs cannot use the validated cache")
    var report: Dictionary=lab.command({"op":"diagnostic_report"})["report"]
    check(report["app_version"]=="1.2.0-active-visibility" and report["cpu_stages"]["by_revision"].size()>0,"CPU subdivisions and app version exported")
    report["appearance_passes"]["rows"]=[]
    for i in range(1000):report["appearance_passes"]["rows"].append({"unused_raw_row":i})
    var portable: Dictionary=lab._portable_report(report)
    check(not portable.has("appearance_passes") and not portable["cpu_stages"].has("rows") and JSON.stringify(portable).to_utf8_buffer().size()<16384,"phone copy keeps all summaries without large duplicate histories")
    check(lab.agent_snapshot()["control_contract"]["booleans"].has("active_visibility"),"comparison controls discoverable")
    lab.queue_free();await process_frame;print("ACTIVE COMMAND ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
