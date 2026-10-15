extends "res://lie_wall09_shared_effect.gd"
const SourceShader=preload("res://shaders/lie_wall10_source.glsl")
const SourceLoader=preload("res://lie_source_surface_loader.gd")
const SharedVisibility=preload("res://lie_shared_visibility_buffers.gd")
var surface_continuity: bool=true
var world_contacts: bool=true
var _source_packets: Dictionary={}
var _legacy_references:=PackedByteArray()
var _visibility_lease: Dictionary={}
var _gpu_world: bool=true
var _gpu_continuity: bool=true
var visibility_uploads: int=0
var _source_work: int=0
func shader_resource() -> RDShaderFile:return SourceShader
func _init(size: int=720) -> void:
    super._init(size)
    if not capture_loaded:return
    _source_packets=SourceLoader.load_packets(capture_root(),catalog)
    if _source_packets.is_empty():failure="Source surface identity/topology contract";capture_loaded=false;return
    if _source_packets["references"].size()!=_references.size() or _source_packets["proof"].get("legacy_reference_sha256")!=catalog["wall05"]["reference_sha256"]:failure="Surface reference job identity";capture_loaded=false;return
    _legacy_references=_references
    _references=_source_packets["references"]
func _options() -> PackedByteArray:
    var bytes: PackedByteArray=super._options();bytes.encode_u32(12,1 if world_contacts else 0);return bytes
func _make_set() -> void:
    if _visibility_lease.is_empty():
        var proof: Dictionary=_source_packets["proof"]["packets"]
        _visibility_lease=SharedVisibility.acquire(_rd,_source_packets["nodes"],_source_packets["leaves"],proof["nodes"]["sha256"],proof["leaves"]["sha256"])
        if not _visibility_lease.get("ok",false):failure="Shared source visibility allocation";return
        allocation_bytes+=int(_visibility_lease["bytes"]);visibility_uploads+=1 if _visibility_lease["uploaded"] else 0
        _gpu_world=world_contacts;_gpu_continuity=surface_continuity
    if not _buffers.has(27):_buffer(27,_source_packets["scene"].size(),_source_packets["scene"])
    if not _buffers.has(28):_buffer(28,MAX_WORK*8)
    _buffers[25]=_visibility_lease["nodes"];_buffers[26]=_visibility_lease["leaves"]
    super._make_set();_buffers.erase(25);_buffers.erase(26)
func set_surface_continuity(value: bool) -> void:
    if surface_continuity==value:return
    surface_continuity=value;_references=_source_packets["references"] if value else _legacy_references
    var bytes: PackedByteArray=_references
    if gpu_ready:RenderingServer.call_on_render_thread(func():
        if not gpu_ready:return
        _rd.buffer_update(_buffers[17],0,bytes.size(),bytes);_gpu_continuity=value
        _geometry_resident=PackedByteArray();_resident=PackedByteArray();_shade_dirty=true)
func set_world_contacts(value: bool) -> void:
    if world_contacts==value:return
    world_contacts=value
    if gpu_ready:RenderingServer.call_on_render_thread(func():
        if not gpu_ready:return
        _rd.buffer_update(_buffers[22],12,4,PackedInt32Array([1 if value else 0]).to_byte_array());_gpu_world=value;_reset_coded_signature())
func _stage(list: int,stage: int,count: int) -> void:
    if stage==2:_source_work=count
    _measured_options["world_contacts"]=_gpu_world;_measured_options["surface_continuity"]=_gpu_continuity
    super._stage(list,stage,count)
func _timed_stage(list: int,stage: int,count: int,name: String) -> void:
    if stage==10:super._timed_stage(list,11,_source_work,"world_visibility")
    super._timed_stage(list,stage,count,name)
func cache_metrics() -> Dictionary:
    var result: Dictionary=super.cache_metrics()
    result["source_surface"]={"continuity":surface_continuity,"world_contacts":world_contacts,"visibility_uploads":visibility_uploads,"shared_visibility":SharedVisibility.metrics(_rd),"scene_bytes":_source_packets.get("scene",PackedByteArray()).size(),"cache_bytes":MAX_WORK*8,"source_geometry":"captured tangent disks, shared master IDs","receiver_queries":"once per winning source patch/light; recovered pixels reuse witnessed source","visibility_precision":"8 bits per light; eighth light 7 bits","camera_independent_occluders":true}
    return result
func _release() -> void:
    super._release()
    if not _visibility_lease.is_empty():SharedVisibility.release(_rd,_visibility_lease.get("key",""));_visibility_lease={}
