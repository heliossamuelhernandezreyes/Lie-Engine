extends RefCounted
## Small, periodic samples; never reads GPU pixels/buffers or assumes missing=0.
const SAMPLE_SECONDS=.5
const MAX_FRAME_SAMPLES=600
const AndroidMetrics=preload("res://lie_robot_android_metrics.gd")
const APP_VERSION="0.1.3-r2-partial-cache"
var android_metrics:=AndroidMetrics.new()
var latest: Dictionary={}
var clock_ticks: int=-1
var _previous_ticks: int=-1
var _previous_usec: int=0
var _previous_reconstructions: int=0
var _frame_ms: Array[float]=[]
var _elapsed: float=0
var _samples: int=0
var _start_usec: int=Time.get_ticks_usec()
var _last_frame_usec: int=0
var _frames_since_sample: int=0
var _previous_api_cpu_ms: int=-1
var _previous_api_usec: int=0
var _api_cpu_percent: float=-1
var _pss_peak: int=-1

static func read_proc(path: String,limit: int=16384) -> PackedByteArray:
    var file:=FileAccess.open(path,FileAccess.READ)
    if file==null:return PackedByteArray()
    # procfs files advertise size zero: bounded reads, not get_as_text/length.
    return file.get_buffer(limit)

static func parse_status(text: String) -> Dictionary:
    var result: Dictionary={}
    for line in text.split("\n"):
        var colon: int=line.find(":")
        if colon<0:continue
        var key: String=line.left(colon)
        if key not in ["VmRSS","VmHWM","RssAnon","RssFile","RssShmem"]:continue
        var fields: PackedStringArray=line.substr(colon+1).strip_edges().replace("\t"," ").split(" ",false)
        if fields.size()==2 and fields[0].is_valid_int() and fields[1]=="kB":result[key]=int(fields[0])*1024
    return result

static func parse_ticks(text: String) -> int:
    # comm can contain spaces and parentheses. Fields after its last ')' start
    # at field 3; utime/stime are fields 14/15 (tail indices 11/12).
    var close: int=text.rfind(")")
    if close<0:return -1
    var fields: PackedStringArray=text.substr(close+1).strip_edges().split(" ",false)
    if fields.size()<13 or not fields[11].is_valid_int() or not fields[12].is_valid_int():return -1
    return int(fields[11])+int(fields[12])

static func parse_auxv(bytes: PackedByteArray,width: int) -> int:
    if width not in [4,8]:return -1
    for offset in range(0,bytes.size()-width*2+1,width*2):
        var key: int=bytes.decode_u64(offset) if width==8 else bytes.decode_u32(offset)
        var value: int=bytes.decode_u64(offset+width) if width==8 else bytes.decode_u32(offset+width)
        if key==0:break
        if key==17 and value>0 and value<=1000000:return value # AT_CLKTCK; same source as bionic sysconf.
    return -1

static func percentile(values: Array[float],fraction: float) -> float:
    if values.is_empty():return -1
    var ordered: Array[float]=values.duplicate();ordered.sort()
    return ordered[clampi(int(ceil(fraction*ordered.size()))-1,0,ordered.size()-1)]

func _init() -> void:
    if not OS.has_feature("android"):clock_ticks=parse_auxv(read_proc("/proc/self/auxv",4096),8 if OS.has_feature("64") else 4)

func reset() -> void:
    _previous_ticks=-1;_previous_usec=0;_frame_ms.clear();_elapsed=0;_samples=0;_start_usec=Time.get_ticks_usec();_last_frame_usec=0;latest={}
    _frames_since_sample=0;_previous_api_cpu_ms=-1;_previous_api_usec=0;_api_cpu_percent=-1;_pss_peak=-1

func shutdown() -> void:android_metrics.shutdown()

static func measured_fps(values: Array[float]) -> float:
    if values.is_empty():return -1
    var total: float=0
    for value in values:total+=value
    return values.size()*1000.0/total if total>0 else -1

static func api_cpu_percent(previous_ms: int,current_ms: int,elapsed_usec: int) -> float:
    if previous_ms<0 or current_ms<previous_ms or elapsed_usec<=0:return -1
    return 100.0*float(current_ms-previous_ms)*1000.0/elapsed_usec

func tick(delta: float,effect: CompositorEffect,viewport: Viewport) -> bool:
    if delta<=0 or not is_finite(delta):return false
    android_metrics.poll()
    _frames_since_sample+=1
    var now: int=Time.get_ticks_usec()
    if _last_frame_usec==0:_last_frame_usec=now;return false
    # Godot's simulation delta can be capped on slow frames and time-scaled.
    # Benchmark wall intervals using the monotonic clock instead.
    var wall_seconds: float=(now-_last_frame_usec)/1000000.0
    _last_frame_usec=now
    _frame_ms.append(wall_seconds*1000)
    if _frame_ms.size()>MAX_FRAME_SAMPLES:_frame_ms.pop_front()
    _elapsed+=wall_seconds
    if _elapsed<SAMPLE_SECONDS:return false
    _elapsed=0
    sample(effect,viewport)
    return true

func sample(effect: CompositorEffect,viewport: Viewport) -> void:
    var now: int=Time.get_ticks_usec()
    var on_android: bool=OS.has_feature("android")
    var status: Dictionary={} if on_android else parse_status(read_proc("/proc/self/status").get_string_from_utf8())
    var ticks: int=-1 if on_android else parse_ticks(read_proc("/proc/self/stat",4096).get_string_from_utf8())
    var gpu: Dictionary=effect.performance_snapshot()
    var seconds: float=(now-_previous_usec)/1000000.0
    var cpu_percent: float=-1
    if clock_ticks>0 and ticks>=0 and _previous_ticks>=0 and ticks>=_previous_ticks and seconds>0:
        cpu_percent=100.0*float(ticks-_previous_ticks)/float(clock_ticks)/seconds
    var native: Dictionary=android_metrics.latest
    var api_usec: int=native.get("cpu_sample_usec",0)
    var api_ms: int=native.get("cpu_time_ms",-1)
    if on_android:
        if api_usec>_previous_api_usec and api_ms>=0:
            _api_cpu_percent=api_cpu_percent(_previous_api_cpu_ms,api_ms,api_usec-_previous_api_usec)
            _previous_api_cpu_ms=api_ms;_previous_api_usec=api_usec
        cpu_percent=_api_cpu_percent
    var pss: int=native.get("pss_bytes",-1)
    if pss>=0:_pss_peak=maxi(_pss_peak,pss)
    var reconstructions: int=effect.frame_count
    var lie_fps: float=float(reconstructions-_previous_reconstructions)/seconds if _previous_usec>0 and seconds>0 else -1
    var gpu_age: float=(now-int(gpu.get("gpu_sample_usec",now)))/1000000.0 if gpu.has("gpu_sample_usec") else -1
    var cores: int=maxi(OS.get_processor_count(),1)
    _samples+=1
    latest={"schema":2,"app_version":APP_VERSION,"sample":_samples,"session_seconds":(now-_start_usec)/1000000.0,
        "fps_screen":Performance.get_monitor(Performance.TIME_FPS),"frame_ms_p50":percentile(_frame_ms,.50),"frame_ms_p95":percentile(_frame_ms,.95),
        "fps_callback_interval":float(_frames_since_sample)/seconds if _previous_usec>0 and seconds>0 else -1,"fps_callback_recent_window":measured_fps(_frame_ms),
        "frame_samples":_frame_ms.size(),"lie_reconstructions_per_second":lie_fps,"lie_reconstructions":reconstructions,
        "engine_process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"engine_physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,
        "cpu_process_one_core_percent":cpu_percent,"cpu_process_total_capacity_percent":cpu_percent/cores if cpu_percent>=0 else -1,
        "logical_cores":cores,"clock_ticks_per_second":clock_ticks,
        "cpu_source":native.get("cpu_source","android API pending") if on_android else "procfs utime+stime/AT_CLKTCK",
        "cpu_sample_age_seconds":(now-api_usec)/1000000.0 if on_android and api_usec>0 else (-1 if on_android else 0),
        "pss_bytes":pss,"pss_sampled_peak_bytes":_pss_peak,"native_heap_bytes":native.get("native_heap_bytes",-1),
        "android_api":native.duplicate(true),"android_api_age_seconds":(now-int(native["sample_usec"]))/1000000.0 if native.has("sample_usec") else -1,
        "rss_bytes":status.get("VmRSS",-1),"rss_peak_bytes":status.get("VmHWM",-1),"rss_anonymous_bytes":status.get("RssAnon",-1),
        "godot_static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"gpu_frame_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()) if effect.gpu_ready else -1,
        "gpu_lie_ms_last":int(gpu.get("lie_gpu_ns",-1))/1000000.0 if gpu.has("lie_gpu_ns") else -1,"gpu_lie_sample_age_seconds":gpu_age,"gpu_lie_samples":gpu.get("gpu_samples",0),
        "gpu_lie_recent_p50_ms":gpu.get("gpu_recent_p50_ms",-1),"gpu_lie_recent_p95_ms":gpu.get("gpu_recent_p95_ms",-1),"gpu_lie_recent_sample_count":gpu.get("gpu_recent_samples",0),
        "cache":gpu.get("cache",{}),"gpu_passes_last_ms":gpu.get("gpu_pass_ms_last",{}),"gpu_passes_recent":gpu.get("gpu_pass_recent",{}),
        "gpu_pass_marker_frame":gpu.get("gpu_pass_marker_frame",-1),"gpu_pass_sample_age_seconds":(now-int(gpu["gpu_pass_sample_usec"]))/1000000.0 if gpu.has("gpu_pass_sample_usec") else -1,
        "gpu_rd_memory_bytes":gpu.get("rd_memory_bytes",-1),"gpu_lie_reserved_bytes":effect.allocation_bytes,"gpu_total_utilization_percent":null,
        "gpu_device":gpu.get("device","no disponible"),"output_size":effect.output_size,"bank_uploads":effect.asset_uploads,"sample_interval_seconds":SAMPLE_SECONDS,
        "scopes":{"rss":"Linux process resident pages, not available in Android API mode.","pss":"Android Debug.getPss proportional resident KiB converted to bytes; shared pages attributed proportionally, not RSS. Peak is max observed samples, not OS high-water mark.","cpu":"Android Process.getElapsedCpuTime milliseconds or Linux utime+stime ticks; this process/all threads, 100% one-core = one busy core. Total denominator logical_cores; not CPU frequency weighting or other apps.","gpu_lie":"Last/rolling compute intervals, not GPU utilization. Per-pass windows include only frames where a pass ran; skipped passes are absent, not zero cost. GPU marker age/frame is separate from latest submitted cache decisions; cached images do not reconstruct.","gpu_memory":"Vulkan allocator/requested LIE buffers; can overlap system RAM. Do not add to PSS/RSS.","frame_pacing":"Monotonic wall intervals between process callbacks, includes scheduling/vsync. Callback FPS/current sample and recent 600-frame FPS use explicit windows. Godot FPS has its own once-per-second window.","unsupported":"-1 or null = unavailable/waiting, never zero load."}}
    _previous_ticks=ticks;_previous_usec=now;_previous_reconstructions=reconstructions
    _frames_since_sample=0

static func mib(value: float) -> String:return "N/D" if value<0 else "%.1f MiB"%(value/1048576.0)
static func ms(value: float) -> String:return "N/D" if value<=0 else "%.2f ms"%value

func display_text() -> String:
    if latest.is_empty():return "Recogiendo mediciones…"
    var cpu: float=latest["cpu_process_total_capacity_percent"]
    var load: String="N/D" if cpu<0 else "%.1f%% / %d núcleos"%[cpu,latest["logical_cores"]]
    var age: float=latest["gpu_lie_sample_age_seconds"]
    var ram: String="RAM PSS: "+mib(latest["pss_bytes"])+"\nPico PSS muestreado: "+mib(latest["pss_sampled_peak_bytes"]) if OS.has_feature("android") else "RAM RSS aprox.: "+mib(latest["rss_bytes"])+"\nPico RSS: "+mib(latest["rss_peak_bytes"])
    var fps: float=latest["fps_callback_interval"]
    var fps_label: String="N/D" if fps<0 else "%.1f"%fps
    return "FPS bucle actual: %s\nFPS bucle ventana: %.1f\nFPS Godot (otra ventana): %.1f\nReconstr. LIE/s: %s\nFrame p50/p95: %s / %s\nCPU proceso: %s\n%s\nGPU frame: %s\nGPU LIE última: %s\nEdad GPU LIE: %.1f s\nMemoria GPU Godot: %s\nLIE reservada: %s\nUso total GPU: N/D"%[
        fps_label,latest["fps_callback_recent_window"],latest["fps_screen"],"N/D" if latest["lie_reconstructions_per_second"]<0 else "%.1f"%latest["lie_reconstructions_per_second"],ms(latest["frame_ms_p50"]),ms(latest["frame_ms_p95"]),load,
        ram,ms(latest["gpu_frame_ms"]),ms(latest["gpu_lie_ms_last"]),age,mib(latest["gpu_rd_memory_bytes"]),mib(latest["gpu_lie_reserved_bytes"])]

func report_text() -> String:return JSON.stringify(latest,"  ",true,true)
