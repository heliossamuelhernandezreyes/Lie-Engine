extends "res://lie_wall21_compact_effect.gd"
const TileKernels=preload("res://lie_screen_tile_kernels.gd")
var screen_tiles: bool=false
var _gpu_tiles: bool=false
var _tile_pipelines: Dictionary={}
var _tile_sets: Dictionary={}
var _tile_buffers: Dictionary={}
var _tile_lengths: Dictionary={}
var _tile_dimensions:=Vector2i.ZERO
var tile_builds: int=0
var tile_allocations: int=0
func _initialize() -> bool:
    _gpu_tiles=screen_tiles
    var ok: bool=super._initialize()
    if ok and query_supported and _tile_sets.size()!=6:failure="Screen tile pipelines: "+failure;_release();return false
    return ok
func _free_tile_sets() -> void:
    for rid in _tile_sets.values():
        if rid.is_valid() and _rd.uniform_set_is_valid(rid):_rd.free_rid(rid)
    _tile_sets.clear()
func _tile_buffer(binding: int,length: int) -> void:
    if _tile_lengths.get(binding,0)==length:return
    if _tile_buffers.has(binding):allocation_bytes-=int(_tile_lengths[binding]);_rd.free_rid(_tile_buffers[binding])
    _tile_buffers[binding]=_rd.storage_buffer_create(length);_tile_lengths[binding]=length;allocation_bytes+=length;tile_allocations+=1
func _make_set() -> void:
    _free_tile_sets();super._make_set()
    if not query_supported or not _kernels_ready:return
    _tile_dimensions=Vector2i(ceili(float(render_size)/8.),ceili(float(render_size)/8.))
    var tiles: int=_tile_dimensions.x*_tile_dimensions.y
    _tile_buffer(41,tiles*16);_tile_buffer(42,MAX_WORK*9*4)
    _tile_buffer(43,(ceili(float(tiles)/64.)+1)*4);_tile_buffer(44,MAX_WORK*16)
    if _tile_pipelines.is_empty():
        for key in TileKernels.SHADERS:
            var spirv: RDShaderSPIRV=TileKernels.SHADERS[key].get_spirv();var error: String=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
            if error!="":failure=key+": "+error;return
            var shader: RID=_rd.shader_create_from_spirv(spirv)
            var pipeline: RID=_rd.compute_pipeline_create(shader);_tile_pipelines[key]={"shader":shader,"pipeline":pipeline}
            if not pipeline.is_valid():failure="Screen tile pipeline "+key;return
    var handles: Dictionary=_buffers.duplicate();handles.merge(_tile_buffers)
    for key in TileKernels.SHADERS:
        var uniforms: Array[RDUniform]=[]
        for binding in TileKernels.BINDINGS[key]:uniforms.append(_uniform(binding,handles[binding]))
        var rid: RID=_rd.uniform_set_create(uniforms,_tile_pipelines[key]["shader"],0)
        if not rid.is_valid():failure="Screen tile descriptors "+key;return
        _tile_sets[key]=rid
func set_screen_tiles(enabled: bool) -> void:
    if screen_tiles==enabled:return
    screen_tiles=enabled
    if gpu_ready:RenderingServer.call_on_render_thread(func():
        if not gpu_ready:return
        _gpu_tiles=enabled;_geometry_resident=PackedByteArray();_resident=PackedByteArray();_shade_dirty=true)
func _effective_tiles() -> bool:return _gpu_tiles and query_supported and _gpu_kernel_mode=="split" and _tile_sets.size()==6
func _tile_dispatch(list: int,key: String,count: int,flags: int=0,indirect: int=-1,groups: bool=false) -> void:
    var label: String="tile_"+key
    _pass_timestamp(label,"begin")
    _rd.compute_list_bind_compute_pipeline(list,_tile_pipelines[key]["pipeline"])
    _rd.compute_list_bind_uniform_set(list,_tile_sets[key],0)
    _rd.compute_list_set_push_constant(list,PackedInt32Array([0,2,_coverage_mode,flags]).to_byte_array(),16)
    if indirect>=0:_rd.compute_list_dispatch_indirect(list,_buffers[indirect],0)
    else:_rd.compute_list_dispatch(list,count if groups else maxi(1,ceili(float(count)/64.)),1,1)
    _pass_barrier(list)
    _pass_timestamp(label,"end")
func _dispatch_kernel(list: int,stage: int,count: int,name: String,flags: int=0,indirect: int=-1) -> void:
    if not _effective_tiles() or stage not in [2,3]:super._dispatch_kernel(list,stage,count,name,flags,indirect);return
    var tiles: int=_tile_dimensions.x*_tile_dimensions.y
    if stage==2:
        _tile_dispatch(list,"reset",tiles)
        _tile_dispatch(list,"project",count,flags,indirect)
        _tile_dispatch(list,"scan",tiles)
        _tile_dispatch(list,"groups",64)
        _tile_dispatch(list,"fill",count,flags,indirect);tile_builds+=1
    else:_tile_dispatch(list,"resolve",tiles,0,-1,true)
func _stage(list: int,stage: int,count: int) -> void:
    _measured_options["screen_tiles"]=_effective_tiles();super._stage(list,stage,count)
func cache_metrics() -> Dictionary:
    var result: Dictionary=super.cache_metrics();var bytes: int=0
    for length in _tile_lengths.values():bytes+=length
    result["screen_tiles"]={"requested":screen_tiles,"effective":_effective_tiles(),"ready":_tile_sets.size()==6,"tile_size":8,"shared_workgroup_bytes":2560,"strategy":"source-footprint reduction in shared memory","builds":tile_builds,"allocations":tile_allocations,"additional_requested_bytes":bytes,"reference_capacity":MAX_WORK*9,"scope":"exact per-screen-tile CSR; one pixel owner; unchanged source disks, depth ties and uint material sums; lists reused on light-only updates"};return result
func _release() -> void:
    _free_tile_sets()
    for entry in _tile_pipelines.values():
        for rid in [entry["pipeline"],entry["shader"]]:
            if rid.is_valid():_rd.free_rid(rid)
    _tile_pipelines.clear()
    for binding in _tile_buffers:
        if _tile_buffers[binding].is_valid():_rd.free_rid(_tile_buffers[binding]);allocation_bytes-=int(_tile_lengths[binding])
    _tile_buffers.clear();_tile_lengths.clear();super._release()
