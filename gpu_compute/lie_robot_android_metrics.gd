extends RefCounted
## Android public APIs through Godot's built-in JNI bridge. No plugin/root.
## All JNI calls are serialized on a worker; PSS collection never stalls UI.
const INTERVAL_USEC=2000000
var enabled: bool=false
var latest: Dictionary={}
var _bridge: Object
var _process_api: Object
var _debug_api: Object
var _task: int=-1
var _next_usec: int=0
var _mutex:=Mutex.new()
var _result: Dictionary={}

func _init() -> void:
    if not OS.has_feature("android"):latest={"error":"not_android"};return
    if not Engine.has_singleton("JavaClassWrapper"):latest={"error":"jni_bridge_unavailable"};return
    _bridge=Engine.get_singleton("JavaClassWrapper")
    _process_api=_bridge.call("wrap","android.os.Process")
    var exception: Variant=_bridge.call("get_exception")
    if exception!=null or _process_api==null:latest={"error":"process_api_unavailable"};return
    _debug_api=_bridge.call("wrap","android.os.Debug")
    exception=_bridge.call("get_exception")
    if exception!=null or _debug_api==null:latest={"error":"memory_api_unavailable"};return
    enabled=true

func _read_number(api: Object,method: String,errors: Array) -> int:
    if not api.call("has_java_method",method):errors.append(method+": unavailable");return -1
    var value: Variant=api.call(method)
    var exception: Variant=_bridge.call("get_exception")
    if exception!=null:errors.append(method+": Java exception");return -1
    if not (value is int or value is float) or not is_finite(float(value)) or value<0:
        errors.append(method+": invalid result");return -1
    return int(value)

func _collect() -> void:
    var start: int=Time.get_ticks_usec();var errors: Array=[]
    var cpu: int=_read_number(_process_api,"getElapsedCpuTime",errors)
    var cpu_usec: int=Time.get_ticks_usec()
    var pss_kb: int=_read_number(_debug_api,"getPss",errors)
    var native_heap: int=_read_number(_debug_api,"getNativeHeapAllocatedSize",errors)
    var now: int=Time.get_ticks_usec()
    # Android Debug.getPss returns zero on failure: do not call it zero RAM.
    if pss_kb==0:errors.append("getPss: no valid pages");pss_kb=-1
    var result: Dictionary={"cpu_time_ms":cpu,"cpu_sample_usec":cpu_usec,"pss_bytes":pss_kb*1024 if pss_kb>0 else -1,
        "native_heap_bytes":native_heap,"sample_usec":now,"sampling_cost_ms":(now-start)/1000.0,"errors":errors,
        "cpu_source":"android.os.Process.getElapsedCpuTime","ram_source":"android.os.Debug.getPss"}
    _mutex.lock();_result=result;_mutex.unlock()

func poll() -> void:
    if not enabled:return
    if _task>=0:
        if not WorkerThreadPool.is_task_completed(_task):return
        WorkerThreadPool.wait_for_task_completion(_task);_task=-1
        _mutex.lock();latest=_result.duplicate(true);_mutex.unlock()
    var now: int=Time.get_ticks_usec()
    if now>=_next_usec:
        _next_usec=now+INTERVAL_USEC
        _task=WorkerThreadPool.add_task(_collect,false,"R2 Android process metrics")

func shutdown() -> void:
    if _task>=0:WorkerThreadPool.wait_for_task_completion(_task);_task=-1
