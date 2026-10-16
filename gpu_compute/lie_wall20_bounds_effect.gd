extends "res://lie_wall19_stream_effect.gd"
const TangentBounds=preload("res://lie_shared_tangent_bounds.gd")
var tight_bounds: bool=false
var _gpu_tight_bounds: bool=false
var _tangent_document: Dictionary={}
var _tangent_lease: Dictionary={}
var _tangent_kernel_set:=RID()
var _tangent_stream_set:=RID()
func _init(size: int=720) -> void:
    super._init(size)
    if not capture_loaded:return
    _tangent_document=TangentBounds.load_document(capture_root(),catalog,_source_packets["proof"],_source_packets["nodes"])
    if _tangent_document.is_empty():failure="Tangent bounds identity/topology contract";capture_loaded=false
func _initialize() -> bool:
    _gpu_tight_bounds=tight_bounds
    var ok: bool=super._initialize()
    if ok and query_supported and (not _tangent_kernel_set.is_valid() or not _tangent_stream_set.is_valid()):failure="Tangent descriptor sets";_release();return false
    return ok
func _free_tangent_sets() -> void:
    for rid in [_tangent_kernel_set,_tangent_stream_set]:
        if rid.is_valid() and _rd.uniform_set_is_valid(rid):_rd.free_rid(rid)
    _tangent_kernel_set=RID();_tangent_stream_set=RID()
func _make_set() -> void:
    _free_tangent_sets();super._make_set()
    if not query_supported or not _kernels_ready or _stream_sets.is_empty():return
    if _tangent_lease.is_empty():
        _tangent_lease=TangentBounds.acquire(_rd,_tangent_document)
        if _tangent_lease.is_empty():failure="Tangent bounds allocation";return
        allocation_bytes+=int(_tangent_lease["bytes"])
    var handles: Dictionary=_buffers.duplicate();handles[23]=transport.surface_light_codes_rid();handles[25]=_tangent_lease["rid"];handles[26]=_visibility_lease["leaves"];handles[30]=_shadow_lease["rid"];handles[38]=_trace_queue
    var uniforms: Array[RDUniform]=[]
    for binding in Kernels.BINDINGS[11]:uniforms.append(_uniform(binding,handles[binding]))
    _tangent_kernel_set=_rd.uniform_set_create(uniforms,_kernels[11]["shader"],0)
    uniforms=[]
    for binding in Stream.BINDINGS["trace"]:uniforms.append(_uniform(binding,handles[binding]))
    _tangent_stream_set=_rd.uniform_set_create(uniforms,_stream_pipelines["trace"]["shader"],0)
func set_tight_bounds(enabled: bool) -> void:
    if tight_bounds==enabled:return
    tight_bounds=enabled
    if gpu_ready:RenderingServer.call_on_render_thread(func():
        if not gpu_ready:return
        _gpu_tight_bounds=enabled
        _geometry_resident=PackedByteArray();_resident=PackedByteArray();_shade_dirty=true
        if query_supported:_rd.buffer_clear(_buffers[39],256,_reference_count*32)
        _rd.buffer_update(_shadow_lease["rid"],4,4,PackedInt32Array([0]).to_byte_array()))
func _dispatch_kernel(list: int,stage: int,count: int,name: String,flags: int=0,indirect: int=-1) -> void:
    if stage==11 and _gpu_tight_bounds and query_supported and _gpu_kernel_mode=="split" and _tangent_kernel_set.is_valid():
        var reference: RID=_kernel_sets[11];_kernel_sets[11]=_tangent_kernel_set
        super._dispatch_kernel(list,stage,count,name,flags,indirect);_kernel_sets[11]=reference;return
    super._dispatch_kernel(list,stage,count,name,flags,indirect)
func _stream_dispatch(list: int,key: String,count: int,label: String,light: int=0,flags: int=0,indirect: RID=RID()) -> void:
    if key=="trace" and _gpu_tight_bounds and _tangent_stream_set.is_valid():
        var reference: RID=_stream_sets[key];_stream_sets[key]=_tangent_stream_set
        super._stream_dispatch(list,key,count,label,light,flags,indirect);_stream_sets[key]=reference;return
    super._stream_dispatch(list,key,count,label,light,flags,indirect)
func _stage(list: int,stage: int,count: int) -> void:
    _measured_options["tight_bounds"]=_gpu_tight_bounds and query_supported and _gpu_kernel_mode=="split"
    super._stage(list,stage,count)
func cache_metrics() -> Dictionary:
    var result: Dictionary=super.cache_metrics()
    result["tangent_bounds"]={"requested":tight_bounds,"effective":tight_bounds and query_supported and kernel_mode=="split","ready":_tangent_kernel_set.is_valid(),"bytes":int(_tangent_document.get("proof",{}).get("bytes",0)),"sha256":_tangent_document.get("proof",{}).get("sha256",""),"scope":"refitted bounds only; unchanged original topology, leaves, TLAS, kernels and disk intersections"};return result
func _release() -> void:
    _free_tangent_sets();super._release()
    if not _tangent_lease.is_empty():TangentBounds.release(_rd,_tangent_lease["key"]);_tangent_lease={}
