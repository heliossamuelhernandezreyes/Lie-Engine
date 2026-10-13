extends RefCounted
## Small, periodic samples; never reads GPU pixels/buffers or assumes missing=0.
const SAMPLE_SECONDS=.5
const MAX_FRAME_SAMPLES=600
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
    clock_ticks=parse_auxv(read_proc("/proc/self/auxv",4096),8 if OS.has_feature("64") else 4)

func reset() -> void:
    _previous_ticks=-1;_previous_usec=0;_frame_ms.clear();_elapsed=0;_samples=0;_start_usec=Time.get_ticks_usec();_last_frame_usec=0;latest={}

func tick(delta: float,effect: CompositorEffect,viewport: Viewport) -> bool:
    if delta<=0 or not is_finite(delta):return false
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
    var status: Dictionary=parse_status(read_proc("/proc/self/status").get_string_from_utf8())
    var ticks: int=parse_ticks(read_proc("/proc/self/stat",4096).get_string_from_utf8())
    var gpu: Dictionary=effect.performance_snapshot()
    var seconds: float=(now-_previous_usec)/1000000.0
    var cpu_percent: float=-1
    if clock_ticks>0 and ticks>=0 and _previous_ticks>=0 and ticks>=_previous_ticks and seconds>0:
        cpu_percent=100.0*float(ticks-_previous_ticks)/float(clock_ticks)/seconds
    var reconstructions: int=effect.frame_count
    var lie_fps: float=float(reconstructions-_previous_reconstructions)/seconds if _previous_usec>0 and seconds>0 else -1
    var gpu_age: float=(now-int(gpu.get("gpu_sample_usec",now)))/1000000.0 if gpu.has("gpu_sample_usec") else -1
    var cores: int=maxi(OS.get_processor_count(),1)
    _samples+=1
    latest={"schema":1,"app_version":"0.1.1-r2-metrics","sample":_samples,"session_seconds":(now-_start_usec)/1000000.0,
        "fps_screen":Performance.get_monitor(Performance.TIME_FPS),"frame_ms_p50":percentile(_frame_ms,.50),"frame_ms_p95":percentile(_frame_ms,.95),
        "frame_samples":_frame_ms.size(),"lie_reconstructions_per_second":lie_fps,"lie_reconstructions":reconstructions,
        "engine_process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"engine_physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,
        "cpu_process_one_core_percent":cpu_percent,"cpu_process_total_capacity_percent":cpu_percent/cores if cpu_percent>=0 else -1,
        "logical_cores":cores,"clock_ticks_per_second":clock_ticks,
        "rss_bytes":status.get("VmRSS",-1),"rss_peak_bytes":status.get("VmHWM",-1),"rss_anonymous_bytes":status.get("RssAnon",-1),
        "godot_static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"gpu_frame_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()) if effect.gpu_ready else -1,
        "gpu_lie_ms_last":int(gpu.get("lie_gpu_ns",-1))/1000000.0 if gpu.has("lie_gpu_ns") else -1,"gpu_lie_sample_age_seconds":gpu_age,"gpu_lie_samples":gpu.get("gpu_samples",0),
        "gpu_rd_memory_bytes":gpu.get("rd_memory_bytes",-1),"gpu_lie_reserved_bytes":effect.allocation_bytes,"gpu_total_utilization_percent":null,
        "gpu_device":gpu.get("device","no disponible"),"output_size":effect.output_size,"bank_uploads":effect.asset_uploads,"sample_interval_seconds":SAMPLE_SECONDS,
        "scopes":{"rss":"Approximate resident process pages; includes shared pages, not Android PSS or private-only RAM.","cpu":"utime+stime of this process, all threads; 100% one-core equals one fully busy logical core. Total-capacity denominator is logical_cores, not other apps or frequency weighting.","gpu_lie":"Last measured LIE compute timestamp interval, not GPU utilization; cached frames do not reconstruct.","gpu_memory":"Vulkan RD allocator and requested LIE buffers/images; can share system RAM. Do not add to RSS.","frame_pacing":"Recent process-frame wall intervals, includes scheduling/vsync, not CPU execution time.","unsupported":"-1 or null means unavailable / waiting, never zero load."}}
    _previous_ticks=ticks;_previous_usec=now;_previous_reconstructions=reconstructions

static func mib(value: float) -> String:return "N/D" if value<0 else "%.1f MiB"%(value/1048576.0)
static func ms(value: float) -> String:return "N/D" if value<=0 else "%.2f ms"%value

func display_text() -> String:
    if latest.is_empty():return "Recogiendo mediciones…"
    var cpu: float=latest["cpu_process_total_capacity_percent"]
    var load: String="N/D" if cpu<0 else "%.1f%% / %d núcleos"%[cpu,latest["logical_cores"]]
    var age: float=latest["gpu_lie_sample_age_seconds"]
    var gpu_label: String=ms(latest["gpu_lie_ms_last"])+(" (hace %.1f s)"%age if age>=0 else "")
    return "FPS pantalla: %.1f\nReconstr. LIE/s: %s\nFrame p95: %s\nCPU proceso: %s\nProceso: %s · física: %s\nRAM RSS aprox.: %s\nPico RSS: %s\nGPU frame: %s\nGPU LIE última: %s\nMemoria GPU Godot: %s\nLIE reservada: %s\nUso total GPU: N/D"%[
        latest["fps_screen"],"N/D" if latest["lie_reconstructions_per_second"]<0 else "%.1f"%latest["lie_reconstructions_per_second"],ms(latest["frame_ms_p95"]),load,
        ms(latest["engine_process_ms"]),ms(latest["engine_physics_ms"]),mib(latest["rss_bytes"]),mib(latest["rss_peak_bytes"]),ms(latest["gpu_frame_ms"]),gpu_label,mib(latest["gpu_rd_memory_bytes"]),mib(latest["gpu_lie_reserved_bytes"])]

func report_text() -> String:return JSON.stringify(latest,"  ",true,true)
