extends SceneTree
const Meter=preload("res://lie_construction_mobile_metrics.gd")
var checks: int=0
var failed: bool=false
func check(value: bool,label: String) -> void:
    checks+=1
    if not value:failed=true;printerr("MOBILE METRICS FAIL ",label)
func _initialize() -> void:
    var m=Meter.new();m.begin({"owner":10,"frames":3},20,{"solves":4})
    for ms in [8.,10.,20.,40.]:m.add_frame(ms)
    m.add_frame(NAN);m.add_frame(-1.);m.add_command(.25)
    var a: Dictionary={"owner":10,"profile":[{"serial":3,"gpu_ns":1000000},{"serial":4,"gpu_ns":2000000,"passes_ns":{"shading":1000000},"executed_passes":["shading"]}],"camera_plan_profile":[{"serial":3,"cpu_usec":999},{"serial":4,"cpu_usec":250}]}
    var l: Dictionary={"profile":[{"serial":4,"gpu_ns":1000000},{"serial":5,"gpu_ns":6000000}]}
    m.collect(a,20,l);m.collect(a,20,l);var result: Dictionary=m.result()
    check(result.display_frame_ms.samples==4 and result.display_frame_ms.p50_ms==10. and result.display_frame_ms.p95_ms==40.,"nearest-rank frame percentiles and invalid samples")
    check(result.appearance_gpu_ms.samples==1 and result.appearance_gpu_ms.p50_ms==2.,"old serial and duplicate GPU timestamps excluded")
    check(result.lighting_gpu_ms.samples==1 and result.lighting_gpu_ms.p50_ms==6.,"transport timing remains separate from appearance")
    check(result.visibility_planning_cpu_ms.samples==1 and result.visibility_planning_cpu_ms.p50_ms==.25,"native planning CPU is serial-filtered, deduplicated and separate from GPU intervals")
    m.collect({"owner":11,"profile":[{"serial":1,"gpu_ns":3000000}]},21,{"profile":[{"serial":1,"gpu_ns":4000000}]});result=m.result()
    check(result.appearance_gpu_ms.samples==2 and result.lighting_gpu_ms.samples==2,"replacement producer and consumer serials do not collide")
    check(result.appearance_passes_gpu_ms.shading.samples==1 and result.appearance_passes_gpu_ms.shading.p50_ms==1.,"per-pass timestamps retained and deduplicated")
    check(not result.appearance_passes_gpu_ms.has("shadow"),"reused passes are unavailable, not synthetic zero times")
    m.begin({"owner":11,"frames":1},21,{"solves":1});result=m.result()
    check(result.appearance_gpu_ms.samples==0 and not result.appearance_gpu_ms.has("p50_ms"),"cached idle does not fabricate a zero-cost solve")
    check(result.command_cpu_ms.samples==0 and result.display_frame_ms.samples==0,"new blocks never mix old options or frames")
    print("CONSTRUCTION MOBILE METRICS ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
