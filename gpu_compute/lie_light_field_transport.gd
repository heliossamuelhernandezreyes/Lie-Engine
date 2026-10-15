extends "res://lie11_light_effect.gd"
## Common finite-surface transport. No wall dimensions or owner-ID arithmetic.
## Eight source-light frontiers; paths from one source still share one moment.
const FieldShader=preload("res://shaders/lie_light_field.glsl")
const MAX_FIELD_LIGHTS: int=8
var optical_enabled: bool=true
var scan_shadow_caps: bool=true
var separate_lights: bool=true
var _field_packets: Dictionary={}
var _field_buffers: Dictionary={}
var _field_factors:=PackedByteArray()
var _field_geometry:=PackedByteArray()
var _field_boxes: int=0
var _direct_enabled: bool=true
var _header_updates: int=0
var _field_edges: int=0
var _gpu_optics: bool=true
var _gpu_separate: bool=true

func _init() -> void:
    super._init();cache_static_transport=true;profile_transport=true

func _transport_file() -> RDShaderFile:return FieldShader

func _valid_csr(bytes: PackedByteArray,n: int) -> bool:
    if bytes.size()<16+4*(n+1) or bytes.size()%4!=0:return false
    var edges: int=bytes.decode_u32(4)
    if bytes.decode_u32(0)!=n or bytes.decode_u32(8)!=4 or bytes.decode_u32(12)!=n+5 or bytes.size()!=4*(n+5)+8*edges:return false
    if bytes.decode_u32(16)!=0 or bytes.decode_u32(16+4*n)!=edges:return false
    for i in range(n):
        if bytes.decode_u32(16+4*i)>bytes.decode_u32(20+4*i):return false
    var begin: int=4*(n+5)
    for i in range(edges):
        var weight: float=bytes.decode_float(begin+8*i+4)
        if bytes.decode_u32(begin+8*i)>=n or not is_finite(weight) or weight<0:return false
    return true

func bind_sources(model: Dictionary, sources: Dictionary) -> bool:
    # Source topology is immutable for this effect. Bind a new effect for edits.
    if gpu_ready or not _field_factors.is_empty() or not Model.valid(model):return false
    var n: int=model["patches"].size()
    for key in ["factors","outgoing","optics","planes","owners","boxes"]:
        if not sources.get(key) is PackedByteArray:return false
    if not _valid_csr(sources["factors"],n) or not _valid_csr(sources["outgoing"],n):return false
    var optics: PackedByteArray=sources["optics"]
    var boxes: PackedByteArray=sources["boxes"]
    var owner: PackedByteArray=sources["owners"]
    var planes: PackedByteArray=sources["planes"]
    if optics.size()!=16+n*64 or owner.size()!=n*4 or boxes.size()<16 or boxes.size()%16!=0:return false
    if optics.decode_u32(4)!=n:return false
    var box_count: int=boxes.decode_u32(0)
    if box_count>4096 or boxes.size()!=16+maxi(box_count,1)*32 or planes.size()!=maxi(box_count,1)*16:return false
    for i in range(n):
        var oid: int=owner.decode_u32(i*4)
        if oid!=0xffffffff and oid>=box_count:return false
        var o: int=16+i*64
        for j in range(16):
            if not is_finite(optics.decode_float(o+j*4)):return false
        for j in range(5):
            if optics.decode_float(o+j*4)<0 or optics.decode_float(o+j*4)>1:return false
        if optics.decode_float(o+20)!=0 or optics.decode_float(o+24)<=0:return false
        var normal:=Vector3(optics.decode_float(o+48),optics.decode_float(o+52),optics.decode_float(o+56))
        if absf(normal.length_squared()-1.)>.0001:return false
    for i in range(box_count):
        var low:=Vector3(boxes.decode_float(16+i*32),boxes.decode_float(20+i*32),boxes.decode_float(24+i*32))
        var high:=Vector3(boxes.decode_float(32+i*32),boxes.decode_float(36+i*32),boxes.decode_float(40+i*32))
        if not low.is_finite() or not high.is_finite() or low.x>=high.x or low.y>=high.y or low.z>=high.z:return false
        var plane:=Vector3(planes.decode_float(i*16),planes.decode_float(i*16+4),planes.decode_float(i*16+8))
        if not plane.is_finite() or absf(plane.length_squared()-1.)>.0001 or not is_finite(planes.decode_float(i*16+12)):return false
    # The gather graph and the normalization graph must be exact transposes.
    var links: Dictionary={}
    var f: PackedByteArray=sources["factors"];var g: PackedByteArray=sources["outgoing"]
    for dst in range(n):
        for e in range(f.decode_u32(16+dst*4),f.decode_u32(20+dst*4)):
            var at: int=4*(n+5)+8*e;var src: int=f.decode_u32(at);var key: int=src*n+dst
            if src==dst or links.has(key):return false
            links[key]=f.decode_u32(at+4)
    for src in range(n):
        for e in range(g.decode_u32(16+src*4),g.decode_u32(20+src*4)):
            var at: int=4*(n+5)+8*e;var dst: int=g.decode_u32(at);var key: int=src*n+dst
            if links.get(key,-1)!=g.decode_u32(at+4):return false
            links.erase(key)
    if not links.is_empty():return false
    _field_geometry=Model.transfer_geometry_key(model);_field_factors=f.duplicate();_field_boxes=box_count;_field_edges=f.decode_u32(4)
    _field_packets={17:boxes.duplicate(),19:optics.duplicate(),21:g.duplicate(),22:planes.duplicate(),24:owner.duplicate()}
    return true

func factor_input_bytes(model: Dictionary) -> PackedByteArray:
    return _field_factors if Model.transfer_geometry_key(model)==_field_geometry else PackedByteArray()

func configure(model: Dictionary) -> bool:
    if (model.get("lights",[]) as Array).size()>MAX_FIELD_LIGHTS or _field_factors.is_empty():return false
    return super.configure(model)

func _initial_transport_buffer(binding: int, bytes: PackedByteArray) -> PackedByteArray:
    if binding==5 or binding==6:bytes.resize(_count*16*MAX_FIELD_LIGHTS)
    return bytes

func _extra_transport_uniforms() -> Array[RDUniform]:
    var uniforms: Array[RDUniform]=[]
    _gpu_optics=optical_enabled;_gpu_separate=separate_lights
    for binding in [17,18,19,20,21,22,23,24]:
        var bytes: PackedByteArray=_field_packets.get(binding,PackedByteArray()).duplicate()
        if bytes.is_empty():bytes.resize(_count*MAX_FIELD_LIGHTS*(32 if binding==18 else 16))
        if binding==19:bytes.encode_u32(0,1 if optical_enabled else 0);bytes.encode_u32(8,1 if scan_shadow_caps else 0);bytes.encode_u32(12,1 if separate_lights else 0)
        if binding==17:bytes.encode_u32(0,_field_boxes if _direct_enabled else 0)
        var rid: RID=_rd.storage_buffer_create(bytes.size(),bytes)
        if not rid.is_valid():failure="Light field allocation";return []
        _field_buffers[binding]=rid;allocation_bytes+=bytes.size();uniforms.append(_uniform(binding,rid))
    return uniforms

func _dispatch(commands: int,stage: int,threads: int,ping: int=0) -> void:
    var active: int=_light_count if _gpu_optics and _gpu_separate else 1
    if stage==3:super._dispatch(commands,5,_count*active,ping)
    super._dispatch(commands,stage,threads*active if stage==2 or stage==3 else threads,ping)

func set_optical_options(directional: bool,scan_caps: bool) -> void:
    if optical_enabled==directional and scan_shadow_caps==scan_caps:return
    optical_enabled=directional;scan_shadow_caps=scan_caps;_queue_headers()

func set_separate_lights(value: bool) -> void:
    if separate_lights==value:return
    separate_lights=value;_queue_headers()

func set_direct_shadow_enabled(value: bool) -> void:
    if _direct_enabled==value:return
    _direct_enabled=value;_queue_headers()

func _queue_headers() -> void:
    if gpu_ready:RenderingServer.call_on_render_thread(Callable(self,"_update_field_headers").bind(optical_enabled,scan_shadow_caps,separate_lights,_direct_enabled))

func _update_field_headers(optics: bool,planes: bool,separate: bool,shadows: bool) -> void:
    if not gpu_ready:return
    _gpu_optics=optics;_gpu_separate=separate
    _rd.buffer_update(_field_buffers[19],0,16,PackedInt32Array([1 if optics else 0,_count,1 if planes else 0,1 if separate else 0]).to_byte_array())
    _rd.buffer_update(_field_buffers[17],0,4,PackedInt32Array([_field_boxes if shadows else 0]).to_byte_array())
    _header_updates+=1;invalidate_transport()

func optical_metrics() -> Dictionary:
    return {"backend":"lie-light-field/1","directional_codes":optical_enabled,"scan_shadow_caps":scan_shadow_caps,"separate_lights":separate_lights,"patches":_count,"edges":_field_edges,"lights":_light_count,"capacity":MAX_FIELD_LIGHTS,"header_updates":_header_updates,"incident_direction":"one directional moment per source light, surface and bounce","scope":"opaque finite patches; no refracted paths","units":"meters; relative linear RGB power"}

func shadow_metrics() -> Dictionary:
    return {"direct_shadow_boxes":_field_boxes,"direct_shadows_enabled":_direct_enabled,"visible_source_triangles":0,"collision_proxies_allocated":0,"owner_mapping":"explicit per surface"}

func _capture_data() -> void:
    if not gpu_ready:return
    var flux: PackedFloat32Array=_rd.buffer_get_data(_buffers[7]).to_float32_array()
    var irradiance: PackedFloat32Array=_rd.texture_get_data(output_rid,0).to_float32_array()
    var channels: PackedFloat32Array=_rd.buffer_get_data(_buffers[5 if _bounces%2==0 else 6]).to_float32_array()
    var total:=PackedFloat32Array();total.resize(_count*4)
    var active: int=_light_count if _gpu_optics and _gpu_separate else 1
    for light in range(active):
        for node in range(_count):
            for k in range(3):total[node*4+k]+=channels[(light*_count+node)*4+k]
    _lock.lock()
    _readback={"flux":flux,"irradiance":irradiance,"frontier":total,"frontier_channels":channels.slice(0,_count*active*4),"frames":frame_count,"allocation_bytes":allocation_bytes,"device":_rd.get_device_name()}
    _lock.unlock()

func _release_gpu() -> void:
    super._release_gpu()
    if _rd!=null:
        for rid in _field_buffers.values():
            if rid.is_valid():_rd.free_rid(rid)
    _field_buffers.clear()
