extends "res://lie_wall04_mortar_effect.gd"
## Same photographed surface equations, source IDs and independently cached geometry.
const SHARED_CACHED_SHADER=preload("res://shaders/lie_wall05_shared_cached.glsl")
const RECOVERY_CAPACITY: int=65536
var _references:=PackedByteArray()
var _geometry_resident:=PackedByteArray()
var _shade_dirty: bool=true
var geometry_rebuilds: int=0
var lighting_resolves: int=0
var recovery_builds: int=0
var recovery_reuses: int=0
var output_resolves: int=0
var _requested_internal: int=1080

func capture_root() -> String:return "res://captures/liewall05/"
func shader_resource() -> RDShaderFile:return SHARED_CACHED_SHADER
func _init(size: int=720) -> void:
    super._init(size)
    render_size=1080 if size==720 else size*2
    _requested_internal=render_size
    var p: String=capture_root()+"sample-refs.bin"
    if not FileAccess.file_exists(p) or FileAccess.get_sha256(p)!=catalog.get("wall05",{}).get("reference_sha256",""):
        failure="WALL05 immutable source reference IDs missing";capture_loaded=false;return
    _references=FileAccess.get_file_as_bytes(p)
    if _references.size()!=int(catalog["wall05"]["reference_bytes"]):failure="WALL05 source reference size";capture_loaded=false

func configure(parameters: PackedByteArray,instances: PackedByteArray,jobs: PackedByteArray,work: int) -> bool:
    if parameters.size()!=256 or instances.size()!=97*96 or jobs.size()!=97*16:return false
    var original: PackedInt32Array=jobs.to_int32_array()
    var lod: int=0 if original[1]==4000 else 1 if original[1]==1300 else 2 if original[1]==240 else -1
    if lod<0:return false
    var entries: Array=catalog["wall05"]["instance_jobs"][lod]
    var expected_work: int=int(entries[-1][3])+int(entries[-1][1])
    if work!=expected_work or parameters.decode_s32(80)!=work or parameters.decode_s32(84)!=97 or parameters.decode_s32(88)!=render_size or parameters.decode_s32(92)!=render_size:return false
    var coded: PackedByteArray=instances.duplicate()
    var ranges:=PackedInt32Array()
    for i in range(97):
        if original[i*4+1]!=int(entries[i][1]) or original[i*4+2]!=i or original[i*4+3]!=int(entries[i][3]):return false
        coded.encode_float(i*96+64,float(i*128))
        coded.encode_float(i*96+72,float(catalog["wall05"]["brick_radius_by_lod"][lod]) if i<96 else 0.)
        for value in entries[i]:ranges.append(int(value))
    if work<1 or work>MAX_WORK:return false
    _mutex.lock();_pending={"parameters":parameters.duplicate(),"instances":coded,"jobs":ranges.to_byte_array(),"work":work};_mutex.unlock();return true

func _make_set() -> void:
    if not _buffers.has(17):_buffer(17,_references.size(),_references)
    if not _buffers.has(18):_buffer(18,render_size*render_size*4)
    if not _buffers.has(19):_buffer(19,RECOVERY_CAPACITY*160)
    if not _buffers.has(20):_buffer(20,16)
    super._make_set()

func _reset_coded_signature() -> void:
    _shade_dirty=true;_resident=PackedByteArray()

func _set_coverage_render(value: bool) -> void:
    super._set_coverage_render(value);_geometry_resident=PackedByteArray()

func force_geometry_rebuild() -> void:
    RenderingServer.call_on_render_thread(func():_geometry_resident=PackedByteArray();_resident=PackedByteArray())

func set_supersampling(enabled: bool) -> void:
    var size: int=1440 if enabled else 1080
    if size==_requested_internal:return
    _requested_internal=size;render_size=size
    if gpu_ready:RenderingServer.call_on_render_thread(Callable(self,"_resize_geometry").bind(size))

func _resize_geometry(size: int) -> void:
    if not gpu_ready:return
    _rd.free_rid(_set);_set=RID()
    for binding in [4,5,7,18]:
        allocation_bytes-=int(_lengths[binding]);_rd.free_rid(_buffers[binding])
        _buffer(binding,size*size*(32 if binding==7 else 4))
    for binding in [8,9,11]:
        var old: RID=_images[binding];var format: RDTextureFormat=_rd.texture_get_format(old)
        allocation_bytes-=format.width*format.height*16;_rd.free_rid(old)
        format.width=size;format.height=size
        _images[binding]=_rd.texture_create(format,RDTextureView.new(),[]);allocation_bytes+=size*size*16
    _make_set();_geometry_resident=PackedByteArray();_resident=PackedByteArray();_shade_dirty=true

func _stage(list: int,stage: int,count: int) -> void:
    _rd.compute_list_set_push_constant(list,PackedInt32Array([stage,2,_coverage_mode,0]).to_byte_array(),16)
    var groups: int=int(ceil(float(count)/64.));var gx: int=mini(groups,65535)
    _rd.compute_list_dispatch(list,gx,int(ceil(float(groups)/float(gx))),1);_rd.compute_list_add_barrier(list)

func _render_callback(_type: int,_data: RenderData) -> void:
    if not capture_loaded or (not gpu_ready and not _initialize()):return
    _mutex.lock();var next: Dictionary=_pending.duplicate();_mutex.unlock()
    if next.is_empty() or next["parameters"].decode_s32(88)!=render_size:return
    _collect_profile()
    var params: PackedByteArray=next["parameters"]
    var signature: PackedByteArray=params.duplicate();signature.append_array(next["instances"]);signature.append_array(next["jobs"])
    if signature==_resident:return
    # Camera/geometry, raster depth tolerance and sample material variation.
    # Light parameters and exposure do not invalidate these persistent buffers.
    var geometry: PackedByteArray=params.slice(0,96)
    geometry.append_array(params.slice(152,160));geometry.append_array(params.slice(208,256))
    geometry.append_array(next["instances"]);geometry.append_array(next["jobs"])
    var rebuild: bool=geometry!=_geometry_resident
    var work: int=next["work"]
    if work>projection_capacity:
        _rd.free_rid(_set);_set=RID();_rd.free_rid(_buffers[3]);allocation_bytes-=int(_lengths[3])
        projection_capacity=mini(MAX_WORK,int(ceil(float(work)/65536))*65536);_buffer(3,projection_capacity*96);_make_set();rebuild=true
    _rd.buffer_update(_buffers[6],0,256,params)
    if rebuild:
        _rd.buffer_update(_buffers[1],0,next["instances"].size(),next["instances"])
        _rd.buffer_update(_buffers[2],0,next["jobs"].size(),next["jobs"])
    _rd.capture_timestamp(_profile_marker("begin"))
    var list: int=_rd.compute_list_begin();_rd.compute_list_bind_compute_pipeline(list,_pipeline);_rd.compute_list_bind_uniform_set(list,_set,0)
    if rebuild:
        for stage in [1,2,3]:_stage(list,stage,work if stage in [2,3] else maxi(render_size*render_size,512*512))
        geometry_rebuilds+=1
    if rebuild or _shade_dirty:
        _stage(list,4,render_size*render_size);_stage(list,6,render_size*render_size)
        _stage(list,8 if rebuild else 9,render_size*render_size)
        lighting_resolves+=1
        if rebuild:recovery_builds+=1
        else:recovery_reuses+=1
    _stage(list,7,output_size*output_size);output_resolves+=1
    _rd.compute_list_end();_rd.capture_timestamp(_profile_marker("end"))
    _resident=signature;_geometry_resident=geometry;_shade_dirty=false
    sample_invocations=work;instance_count=97;frame_count+=1

func cache_metrics() -> Dictionary:
    return {"geometry_rebuilds":geometry_rebuilds,"lighting_resolves":lighting_resolves,"recovery_builds":recovery_builds,"recovery_reuses":recovery_reuses,"output_resolves":output_resolves,"internal_size":render_size,"source_bank_bytes":_samples.size(),"reference_bytes":_references.size(),"brick_master_count":1,"brick_instances":96,"recovery_capacity":RECOVERY_CAPACITY}

func _capture() -> void:
    super._capture()
    if gpu_ready:
        var counters: PackedInt32Array=_rd.buffer_get_data(_buffers[20]).to_int32_array()
        _mutex.lock();_readback["cache"]=cache_metrics();_readback["recovered_pixels"]=counters[0];_readback["recovery_overflow"]=counters[1];_mutex.unlock()

func _release() -> void:
    super._release();_geometry_resident=PackedByteArray();_shade_dirty=true
