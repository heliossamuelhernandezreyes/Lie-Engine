extends "res://lie_wall10_shared_effect.gd"
const PersistentShader=preload("res://shaders/lie_wall11_persistent.glsl")
const Identity=preload("res://lie_sample_identity.gd")
const ShadowCache=preload("res://lie_shared_shadow_cache.gd")
var persistent_visibility: bool=true
var block_access: bool=true
var visibility_diagnostics: bool=false
var shadow_allocations: int=0
var sample_identity=Identity.new()
var _schedules: Dictionary={}
var _schedule_bytes:=PackedByteArray()
var _active_schedule: Dictionary={}
var _shadow_lease: Dictionary={}
var _shadow_mode: bool=true
var _gpu_persistent: bool=true
var _gpu_blocks: bool=true
var _gpu_diagnostics: bool=false
var _reference_count: int=0
var _domains: Dictionary={}
func shader_resource() -> RDShaderFile:return PersistentShader
func _init(size: int=720) -> void:
    super._init(size)
    if not capture_loaded:return
    var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(capture_root()+"asset-contract.json"))
    if not sample_identity.configure(manifest,catalog):failure="Stable sample identity contract";capture_loaded=false;return
    _reference_count=_references.size()/4
    for entries in catalog["wall05"]["instance_jobs"]:
        var jobs:=PackedInt32Array()
        for entry in entries:
            for value in entry:jobs.append(int(value))
        var schedule: Dictionary=Identity.blocks(jobs.to_byte_array(),_reference_count,entries.size())
        if schedule.is_empty() or schedule["groups"]>65535:failure="Source block schedule contract";capture_loaded=false;return
        schedule["offset"]=_schedule_bytes.size()/8;_schedule_bytes.append_array(schedule["bytes"])
        _schedules[jobs[1]]=schedule
    var proof: Dictionary=_source_packets["proof"]
    for mode in [true,false]:
        var references_sha: String=proof["packets"]["references"]["sha256"] if mode else proof["legacy_reference_sha256"]
        _domains[mode]=("lie-visibility/1|"+catalog["sha256"]+"|"+references_sha+"|"+proof["packets"]["scene"]["sha256"]).sha256_text()
func _control_bytes() -> PackedByteArray:
    return PackedInt32Array([1 if persistent_visibility else 0,1 if visibility_diagnostics else 0,_reference_count,1 if block_access else 0]).to_byte_array()
func _make_set() -> void:
    if not _buffers.has(29):_buffer(29,_schedule_bytes.size(),_schedule_bytes)
    if not _buffers.has(31):
        var control: PackedByteArray=_control_bytes();control.resize(128);_buffer(31,128,control)
        _gpu_persistent=persistent_visibility;_gpu_blocks=block_access;_gpu_diagnostics=visibility_diagnostics
    if _shadow_lease.is_empty():
        _shadow_mode=_gpu_continuity if gpu_ready else surface_continuity
        _shadow_lease=ShadowCache.acquire(_rd,_domains[_shadow_mode],_reference_count)
        if not _shadow_lease.get("ok",false):failure="Shared persistent shadow allocation";return
        allocation_bytes+=_shadow_lease["bytes"];shadow_allocations+=1 if _shadow_lease["uploaded"] else 0
    _buffers[30]=_shadow_lease["rid"]
    super._make_set();_buffers.erase(30)
func set_identity_options(persistent: bool,blocks: bool,diagnostics: bool=false) -> void:
    if persistent_visibility==persistent and block_access==blocks and visibility_diagnostics==diagnostics:return
    var geometry_changed: bool=block_access!=blocks
    persistent_visibility=persistent;block_access=blocks;visibility_diagnostics=diagnostics
    var control: PackedByteArray=_control_bytes()
    if gpu_ready:RenderingServer.call_on_render_thread(func():
        if not gpu_ready:return
        _rd.buffer_update(_buffers[31],0,16,control)
        _gpu_persistent=persistent;_gpu_blocks=blocks;_gpu_diagnostics=diagnostics
        if geometry_changed:_geometry_resident=PackedByteArray()
        _reset_coded_signature())
func clear_visibility_cache() -> void:
    if gpu_ready:RenderingServer.call_on_render_thread(func():
        if not gpu_ready:return
        _rd.buffer_update(_shadow_lease["rid"],4,4,PackedInt32Array([0]).to_byte_array());_reset_coded_signature())
func _render_callback(type: int,data: RenderData) -> void:
    if not capture_loaded or (not gpu_ready and not _initialize()):return
    if _shadow_mode!=_gpu_continuity:
        # Free the descriptor set before replacing its borrowed cache RID.
        if _set.is_valid():_rd.free_rid(_set);_set=RID()
        allocation_bytes-=int(_shadow_lease["bytes"]);ShadowCache.release(_rd,_shadow_lease["key"]);_shadow_lease={};_make_set()
    _mutex.lock();var next: Dictionary=_pending.duplicate();_mutex.unlock()
    if next.is_empty():return
    var jobs: PackedByteArray=next["jobs"];_active_schedule=_schedules.get(jobs.decode_u32(4),{})
    if _active_schedule.is_empty():failure="Missing resident source block schedule";return
    super._render_callback(type,data)
func _stage(list: int,stage: int,count: int) -> void:
    _measured_options["persistent_visibility"]=_gpu_persistent;_measured_options["block_access"]=_gpu_blocks
    _measured_options["visibility_diagnostics"]=_gpu_diagnostics
    super._stage(list,stage,count)
func _extra_stage(list: int,stage: int,count: int,name: String) -> void:
    _rd.capture_timestamp(pass_profile.marker(get_instance_id(),frame_count+1,name,"begin"))
    _rd.compute_list_set_push_constant(list,PackedInt32Array([stage,2,_coverage_mode,0]).to_byte_array(),16)
    _rd.compute_list_dispatch(list,ceili(float(count)/64.),1,1);_rd.compute_list_add_barrier(list)
    _rd.capture_timestamp(pass_profile.marker(get_instance_id(),frame_count+1,name,"end"))
func _timed_stage(list: int,stage: int,count: int,name: String) -> void:
    if stage==10:
        _extra_stage(list,13,64,"visibility_keys")
        _extra_stage(list,12,_reference_count,"visibility_invalidate")
    if stage in [2,3] and _gpu_blocks:
        _rd.capture_timestamp(pass_profile.marker(get_instance_id(),frame_count+1,name,"begin"))
        _rd.compute_list_set_push_constant(list,PackedInt32Array([stage,2,_coverage_mode,int(_active_schedule["offset"])+1]).to_byte_array(),16)
        _rd.compute_list_dispatch(list,int(_active_schedule["groups"]),1,1);_rd.compute_list_add_barrier(list)
        _rd.capture_timestamp(pass_profile.marker(get_instance_id(),frame_count+1,name,"end"));return
    super._timed_stage(list,stage,count,name)
func cache_metrics() -> Dictionary:
    var result: Dictionary=super.cache_metrics()
    result["persistent_visibility"]={"enabled":persistent_visibility,"block_access":block_access,"diagnostics":visibility_diagnostics,"reference_entries":_reference_count,"shared":ShadowCache.metrics(_rd),"allocation_count":shadow_allocations,"block_table_bytes":_schedule_bytes.size(),"active_groups":_active_schedule.get("groups",0),"padding":_active_schedule.get("padding",0),"scope":"stable source-reference/instance identity; camera independent; per-light position and metric invalidation"}
    return result
func _capture() -> void:
    if not gpu_ready:return
    super._capture()
    var counters: PackedInt32Array=_rd.buffer_get_data(_buffers[31],0,128).to_int32_array()
    var header: PackedInt32Array=_rd.buffer_get_data(_shadow_lease["rid"],0,256).to_int32_array()
    var first: Dictionary=SharedSamples.resolve(_rd,_sample_handle,0)
    var last: Dictionary=SharedSamples.resolve(_rd,_sample_handle,int(catalog["sample_count"])-1)
    var wrong: Dictionary=_sample_handle.duplicate();wrong["generation"]+=1
    var identity: Dictionary={"generation":_sample_handle["generation"],"first_offset":first.get("byte_offset",-1),"last_offset":last.get("byte_offset",-1),"rid_matches":first.get("rid",RID())==_buffers[0],"stale_rejected":SharedSamples.resolve(_rd,wrong,0).is_empty(),"outside_rejected":SharedSamples.resolve(_rd,_sample_handle,int(catalog["sample_count"])).is_empty()}
    _mutex.lock();_readback["sample_identity"]=identity
    _readback["visibility_work"]={"instrumented":_gpu_diagnostics,"hits":Array(counters.slice(4,12)),"queries":Array(counters.slice(12,20)),"zero_power_skips":Array(counters.slice(20,28)),"dirty_lights":header[0],"prepare_count":header[3],"invalidation_count":header[40],"per_light_invalidations":Array(header.slice(41,49))};_mutex.unlock()
func _release() -> void:
    super._release()
    if not _shadow_lease.is_empty():ShadowCache.release(_rd,_shadow_lease["key"]);_shadow_lease={}
