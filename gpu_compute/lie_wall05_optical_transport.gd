extends "res://lie_wall04_transport.gd"
## LIE35 passive angular budgets on the SAME real sparse scene graph and cache.
const ANGULAR_SPARSE=preload("res://shaders/lie_wall05_directional_sparse.glsl")
var optical_enabled: bool=false
var scan_shadow_caps: bool=false
var _optical_buffers: Dictionary={}
var _optical_packets: Dictionary={}
var _optical_header_updates: int=0

func _transport_file() -> RDShaderFile:return ANGULAR_SPARSE

func _extra_transport_uniforms() -> Array[RDUniform]:
    var uniforms: Array[RDUniform]=super._extra_transport_uniforms()
    var root: String="res://captures/liewall05/"
    var cat: Variant=JSON.parse_string(FileAccess.get_file_as_string(root+"catalog.json"))
    if not cat is Dictionary:failure="WALL05 optical source catalog missing";return uniforms
    for pair in [[19,"optics.bin"],[21,"outgoing-csr.bin"],[22,"shadow-caps.bin"]]:
        var binding: int=pair[0];var name: String=pair[1];var path: String=root+name
        var proof: Dictionary=cat["wall05"][name]
        if FileAccess.get_sha256(path)!=proof["sha256"]:failure="WALL05 optical source SHA "+name;return uniforms
        var data: PackedByteArray=FileAccess.get_file_as_bytes(path)
        if data.size()!=int(proof["bytes"]):failure="WALL05 optical source bytes "+name;return uniforms
        if binding==19:
            data.encode_u32(0,1 if optical_enabled else 0);data.encode_u32(8,1 if scan_shadow_caps else 0)
        _optical_packets[binding]=data
    for binding in [18,19,20,21,22]:
        var data: PackedByteArray=_optical_packets.get(binding,PackedByteArray())
        if data.is_empty():data.resize(_count*(32 if binding==18 else 16))
        var rid: RID=_rd.storage_buffer_create(data.size(),data)
        _optical_buffers[binding]=rid;allocation_bytes+=data.size();uniforms.append(_uniform(binding,rid))
    return uniforms

func set_optical_options(directional: bool,scan_caps: bool) -> void:
    if optical_enabled==directional and scan_shadow_caps==scan_caps:return
    optical_enabled=directional;scan_shadow_caps=scan_caps
    if gpu_ready:RenderingServer.call_on_render_thread(Callable(self,"_update_optical_header").bind(directional,scan_caps))

func _update_optical_header(directional: bool,scan_caps: bool) -> void:
    if not gpu_ready:return
    _rd.buffer_update(_optical_buffers[19],0,16,PackedInt32Array([1 if directional else 0,_count,1 if scan_caps else 0,0]).to_byte_array())
    _optical_header_updates+=1;invalidate_transport()

func _dispatch(commands: int,stage: int,threads: int,ping: int=0) -> void:
    if stage==3:super._dispatch(commands,5,threads,ping)
    super._dispatch(commands,stage,threads,ping)

func optical_metrics() -> Dictionary:
    return {"directional_codes":optical_enabled,"scan_shadow_caps":scan_shadow_caps,"optical_header_updates":_optical_header_updates,"patches":_count,"graph":"original WALL04 CSR; outgoing transpose for passive lobe caps","incident_direction":"single power-weighted direction per patch/frontier","scope":"opaque wall; no transmitted or refracted paths"}

func _release_gpu() -> void:
    super._release_gpu()
    if _rd!=null:
        for rid in _optical_buffers.values():
            if rid.is_valid():_rd.free_rid(rid)
    _optical_buffers.clear()
