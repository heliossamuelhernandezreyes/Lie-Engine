extends SceneTree
const Monitor=preload("res://lie_robot_performance.gd")
const Lab=preload("res://lie_robot_world_lab.gd")
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func expect(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;push_error("R2 METRICS: "+label)
func run() -> void:
    var status: Dictionary=Monitor.parse_status("Name:\ttest\nVmRSS:\t1234 kB\nVmHWM: 2345 kB\nRssAnon: 333 kB\nVmSize: 999 kB\n")
    expect(status["VmRSS"]==1234*1024 and status["VmHWM"]==2345*1024 and not status.has("VmSize"),"RSS/peak are resident bytes, not virtual memory")
    expect(Monitor.parse_status("").is_empty(),"Unreadable proc data remains unavailable")
    expect(Monitor.parse_ticks("1 (name (with) spaces) R 0 0 0 0 0 0 0 0 0 0 7 13 999 999")==20,"CPU fields exclude child ticks and tolerate command parentheses")
    expect(Monitor.parse_ticks("")==-1,"Invalid CPU data is not zero usage")
    var aux:=PackedByteArray();aux.resize(48);aux.encode_u64(0,6);aux.encode_u64(8,4096);aux.encode_u64(16,17);aux.encode_u64(24,250)
    expect(Monitor.parse_auxv(aux,8)==250,"Actual AT_CLKTCK controls CPU units, no 100 Hz assumption")
    var aux32:=PackedByteArray();aux32.resize(16);aux32.encode_u32(0,17);aux32.encode_u32(4,100)
    expect(Monitor.parse_auxv(aux32,4)==100 and Monitor.parse_auxv(PackedByteArray(),8)==-1,"32-bit and absent auxiliary vectors")
    expect(Monitor.percentile([1.0,8.0,2.0,3.0],.95)==8 and Monitor.percentile([], .95)==-1,"Wall frame p95 and missing samples")
    var lab:=Lab.new();lab.touch_mode=true;root.add_child(lab)
    for i in range(3):await physics_frame
    var monitor:=Monitor.new();monitor.sample(lab.effect,root)
    var first: Dictionary=monitor.latest.duplicate(true)
    expect(first["rss_bytes"]>0 and first["rss_peak_bytes"]>=first["rss_bytes"],"Bounded reads obtain real zero-length procfs RSS")
    expect(monitor.clock_ticks>0 and first["cpu_process_one_core_percent"]==-1,"Clock source reads actual auxv; first CPU sample waits")
    var until: int=Time.get_ticks_usec()+150000;var accumulator: float=0
    while Time.get_ticks_usec()<until:accumulator+=sqrt(float(Time.get_ticks_usec()%10000))
    monitor.sample(lab.effect,root)
    expect(monitor.latest["cpu_process_one_core_percent"]>0 and accumulator>0,"A real CPU workload produces nonzero measured process utilization")
    monitor.tick(.001,lab.effect,root)
    var wait_until: int=Time.get_ticks_usec()+50000
    while Time.get_ticks_usec()<wait_until:accumulator+=.01
    monitor.tick(.001,lab.effect,root)
    expect(Monitor.percentile(monitor._frame_ms,.95)>=50,"Frame pacing uses elapsed clock time even when simulation delta is only 1 ms")
    expect(is_equal_approx(monitor.latest["cpu_process_total_capacity_percent"]*monitor.latest["logical_cores"],monitor.latest["cpu_process_one_core_percent"]),"Core normalization is explicit")
    expect(monitor.latest["gpu_total_utilization_percent"]==null and monitor.display_text().contains("Uso total GPU: N/D"),"Unavailable GPU utilization is never inferred from frame time")
    expect(JSON.parse_string(monitor.report_text())["schema"]==2,"Copy report is valid JSON with measurement scopes")
    expect(Monitor.api_cpu_percent(100,600,1000000)==50 and Monitor.api_cpu_percent(-1,100,1000000)==-1,"Android CPU milliseconds keep units and wait for baseline")
    expect(is_equal_approx(Monitor.measured_fps([50.0,150.0]),10.0),"Recent-loop FPS uses total wall time, not reciprocal median")
    monitor.reset();expect(monitor.latest.is_empty(),"Reset clears rolling samples")
    var report: Dictionary={"checks":checks,"failed":failed,"first_sample":first,"physical_android_tested":false}
    var file:=FileAccess.open("res://robot-performance-verification.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close();print("R2 METRICS ",JSON.stringify(report))
    root.remove_child(lab);lab.free();await process_frame;quit(1 if failed else 0)
