extends "res://lie_wall02_coded_effect.gd"
## Reconstruct only tiny INTERNAL unsampled intervals in existing genuine
## 3D scan footprints. Uses the ORIGINAL LIE11 coded RGB lighting already
## applied at stage 6. No color invention from AI or box faces.
const HoleShader: RDShaderFile=preload("res://shaders/lie_wall03_coverage.glsl")
var coverage_enabled: bool=true
var _coverage_mode: int=1
var hole_dispatches: int=0

func capture_root() -> String:
    return "res://captures/liewall03/"

func shader_resource() -> RDShaderFile:
    return HoleShader

func set_coverage_enabled(value: bool) -> void:
    if coverage_enabled==value:
        return
    coverage_enabled=value
    RenderingServer.call_on_render_thread(
        Callable(self,"_set_coverage_render").bind(value))

func _set_coverage_render(value: bool) -> void:
    _coverage_mode=1 if value else 0
    _resident=PackedByteArray()

func coverage_profile() -> Dictionary:
    _mutex.lock()
    var data: Array=_profiles.duplicate(true)
    _mutex.unlock()
    var times: Array[float]=[]
    for record in data:
        if record is Dictionary and record.has("gpu_ns"):
            times.append(float(record["gpu_ns"])/1.0e6)
    times.sort()
    var result: Dictionary={"gpu_timestamps_available":not times.is_empty(),
        "sample_count":times.size(),
        "coverage_enabled":coverage_enabled,
        "full_resolution_hole_dispatches":hole_dispatches,
        "frame_count":frame_count,
        "gpu_allocation_MiB":float(allocation_bytes)/1048576.0}
    if not times.is_empty():
        result["p50_gpu_ms"]=times[times.size()/2]
        result["min_gpu_ms"]=times[0]
        result["p95_gpu_ms"]=times[mini(times.size()-1,int(floor(times.size()*.95)))]
    return result

func _render_callback(_type: int,_data: RenderData) -> void:
    if not capture_loaded or (not gpu_ready and not _initialize()):
        return
    _mutex.lock()
    var next: Dictionary=_pending.duplicate()
    _mutex.unlock()
    if next.is_empty():
        return
    _collect_profile()
    var signature: PackedByteArray=next["parameters"].duplicate()
    signature.append_array(next["instances"])
    signature.append_array(next["jobs"])
    if signature==_resident:
        return
    var work: int=next["work"]
    if work>projection_capacity:
        _rd.free_rid(_set)
        _set=RID()
        _rd.free_rid(_buffers[3])
        allocation_bytes-=int(_lengths[3])
        projection_capacity=mini(MAX_WORK,int(ceil(float(work)/65536))*65536)
        _buffer(3,projection_capacity*96)
        _make_set()
    _rd.buffer_update(_buffers[6],0,256,next["parameters"])
    _rd.buffer_update(_buffers[1],0,next["instances"].size(),next["instances"])
    _rd.buffer_update(_buffers[2],0,next["jobs"].size(),next["jobs"])
    _rd.capture_timestamp("lie22-begin")
    var list: int=_rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(list,_pipeline)
    _rd.compute_list_bind_uniform_set(list,_set,0)
    for stage in [1,2,3,4,6,8,7]:
        var count: int=work if stage in [2,3] else maxi(render_size*render_size,512*512) if stage==1 else output_size*output_size if stage==7 else render_size*render_size
        var mode: int=_coverage_mode if stage==8 else 0
        _rd.compute_list_set_push_constant(list,PackedInt32Array([stage,2,mode,0]).to_byte_array(),16)
        var groups: int=int(ceil(float(count)/64))
        var gx: int=mini(groups,65535)
        var gy: int=int(ceil(float(groups)/float(gx)))
        if gx<1 or gy<1 or gy>65535:
            failure="LIE-WALL03 dispatch exceeds Vulkan workgroup limit"
            _rd.compute_list_end()
            return
        _rd.compute_list_dispatch(list,gx,gy,1)
        _rd.compute_list_add_barrier(list)
        if stage==8:
            hole_dispatches+=1
    _rd.compute_list_end()
    _rd.capture_timestamp("lie22-end")
    _resident=signature
    sample_invocations=work
    instance_count=next["instances"].size()/96
    frame_count+=1
