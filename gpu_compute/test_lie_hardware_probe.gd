extends SceneTree
const Hardware=preload("res://lie_hardware_diagnostics.gd")
var checks: int=0
var failed: bool=false
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("HARDWARE PROBE FAIL ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var hardware:=Hardware.new();var status: Dictionary=hardware.probe()
    check(ClassDB.class_exists("LieGPUProbe") and status.get("native_extension",false),"actual GDExtension loaded in Godot")
    check(status.get("libGPUCounters_sha")=="378c7b59e2dae87cbbffb0ac9cf96ed13c939823","pinned counter backend")
    check(status.get("godot_cpp_sha")=="e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77","pinned binding backend")
    # CI deliberately has no Mali device. Missing hardware must be explicit.
    check(not status.get("available",true) and not str(status.get("reason","")).is_empty(),"unsupported host reported without synthetic counters")
    var begin: Dictionary=hardware.begin();var end: Dictionary=hardware.end()
    check(not begin.get("available",true) and not end.get("available",true),"unavailable sampler cannot manufacture measurements")
    hardware.release_counters();hardware.release_counters()
    var telemetry: Dictionary=hardware.telemetry()
    for key in ["gpu_frequency","gpu_temperature","thermal_status"]:
        check(telemetry.has(key),"telemetry availability explicit "+key)
        if not telemetry.get(key,{}).get("available",false):check(not telemetry[key].has("value") and telemetry[key].has("reason"),"missing telemetry is not zero "+key)
    var file:=FileAccess.open("res://hardware-probe-native.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"status":status,"telemetry":telemetry,"physical_android_tested":false},"  ",true,true));file.close()
    print("HARDWARE PROBE ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
