extends SceneTree
const Policy=preload("res://lie_power_response_policy.gd")
const Diagnostics=preload("res://lie_mobile_diagnostics.gd")
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("RESPONSE COMMAND FAIL ",label)
func packet(rgb: Vector3,position: Vector3=Vector3.ZERO) -> PackedByteArray:
    return PackedFloat32Array([position.x,position.y,position.z,1.,rgb.x,rgb.y,rgb.z,0.]).to_byte_array()
func run() -> void:
    var a: PackedByteArray=packet(Vector3(1.,.5,.25))
    check(Policy.compatible(a,packet(Vector3(2.,1.,.5))),"scalar power accepted")
    check(Policy.compatible(a,packet(Vector3.ZERO)),"positive source may turn off")
    check(not Policy.compatible(packet(Vector3.ZERO),a),"zero anchor cannot turn on")
    check(not Policy.compatible(a,packet(Vector3(2.,1.,.6))),"chromaticity change rejected")
    check(not Policy.compatible(a,packet(Vector3(1.,.5,.25),Vector3.ONE)),"position change rejected")
    check(not Policy.compatible(a,packet(Vector3(-1.,.5,.25))),"negative power rejected")
    check(not Policy.compatible(a,packet(Vector3(INF,.5,.25))),"infinite power rejected")
    check(not Policy.compatible(a,packet(Vector3(NAN,.5,.25))),"NaN power rejected")
    check(not Policy.compatible(a,packet(Vector3.ONE*.000001)),"near zero threshold rejected")
    check(not Policy.compatible(PackedByteArray(),PackedByteArray()),"empty anchor rejected")
    check(not Policy.compatible(a,a.slice(0,31)),"malformed packet rejected")
    var two: PackedByteArray=a.duplicate();two.append_array(a)
    var scaled: PackedByteArray=packet(Vector3(2.,1.,.5));scaled.append_array(packet(Vector3(.5,.25,.125)))
    check(Policy.compatible(two,scaled),"independent scalar powers accepted")
    var rows: Array=[]
    for name in ["solve","output"]:rows.append({"serial":1,"pass":name,"gpu_ns":1000000,"context":{"event_kind":"geometry","timing_scope":"whole_appearance"}})
    var summary: Dictionary=Diagnostics.summarize({"rows":rows})
    check(summary["groups"][0]["total_instrumented_gpu"]["p50_ms"]==1.,"whole interval never added to its stages")
    rows.remove_at(0);check(not Diagnostics.summarize({"rows":rows})["available"],"missing whole interval rejected")
    var lab=load("res://lie_wall23_android_lab.tscn").instantiate();root.add_child(lab);await process_frame
    check(lab.effect.capture_loaded and lab.state["power_response"] and not lab.state["stage_timestamps"] and not lab.state["lean_barriers"] and lab.state["tight_bounds"],"shipping defaults and verified source bank")
    var original: Dictionary=lab.state.duplicate(true);var revision: int=lab.revision
    for key in ["power_response","stage_timestamps","lean_barriers"]:
        for value in [1,"yes",null]:check(not lab.command({"op":"set_values","values":{key:value,"light_power":2.}})["ok"] and lab.state==original and lab.revision==revision,"invalid response transaction atomic")
    for mode in lab.RESPONSE_MODES:
        var values: Dictionary=lab._response_mode_state(original,mode)
        check(values["tight_bounds"] and not values["screen_tiles"] and not values["compact_shadows"] and not values["visibility_stream"] and values["kernel_mode"]=="split","comparison isolates response/submission with fixed geometry options")
    check(lab.command({"op":"compare_kernels","quick":true})["ok"],"four-mode comparison accepted")
    check(not lab.command({"op":"set_values","values":{"power_response":false}})["ok"],"external mutation locked during measurement")
    lab.command({"op":"benchmark_cancel"})
    for i in range(24):await process_frame
    check(not lab.benchmark_busy and lab.state==original and lab._comparison_report.get("cancelled",false) and lab._comparison_report.get("restored",false),"cancel restores exact scene and options")
    var report: Dictionary=lab._portable_report(lab._build_report())
    check(report["app_version"]=="2.0.0-power-response" and report["cache"].has_all(["power_response","submission"]),"version and allocation scopes copied")
    check(JSON.stringify(report).to_utf8_buffer().size()<32768 and report["kernel_comparison"]["scene"]==original,"copy retains exact scene within clipboard budget")
    lab.queue_free();await process_frame;print("RESPONSE COMMAND ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
