extends "res://lie15_light_effect.gd"
## Geometry, materials and instances publish together on the render thread.
## Three GPU stages rebuild reciprocal bounded form factors only when needed.
const Shader18: RDShaderFile=preload("res://shaders/lie18_transport.glsl")
var render_poses: Array[Transform3D]=[]
var render_slots: Array=[]
var render_signature: String=""
var graph_rebuilds: int=0
var _factor_caps: RID
var profile_enabled: bool=false
var diagnostic_force_graph: bool=false
var _resident_inputs: Dictionary={}
var _resident_geometry:=PackedByteArray()
var _metrics: Dictionary={}
var _profile_rows: Array=[]
var _profile_meta: Dictionary={}
var _last_profile_frame: int=-1
var _upload_bytes: int=0
var _graph_reuses: int=0

func configure_workshop(model: Dictionary) -> bool:
    var started: int=Time.get_ticks_usec()
    if not Model.valid(model) or not model.get("geometry_bytes") is PackedByteArray: return false
    var count: int=model["patches"].size()
    if _count!=0 and count!=_count: return false
    _count=count; _triangle_count=0
    var config: PackedByteArray=PackedInt32Array([count,model["lights"].size(),int(model["bounces"]),0]).to_byte_array()
    var policy: Dictionary=model["secondary_radii"]
    config.append_array(PackedFloat32Array([.0025,0,0,1,float(policy["radius_max"]),float(policy["radius_decay"]),float(policy["power_reference"]),float(model["optical_sheets"].size())]).to_byte_array())
    var next: Dictionary={0:Model.patch_bytes(model),1:Model.light_bytes(model),8:config,9:Model.blocker_bytes(model),11:Model.triangle_bytes(model),12:Model.radius_bytes(model),13:Optics.bytes(model["optical_sheets"]),
        "geometry":model["geometry_bytes"],"lights":model["lights"].size(),"bounces":int(model["bounces"]),"instance":model["instance_bytes"],"poses":model["poses"].duplicate(),"slots":model["slots"].duplicate(),"signature":model["signature"],"cpu_pack_us":Time.get_ticks_usec()-started}
    # Compare with consumed inputs on the render thread, not with the previous
    # configure call: several edits can replace an unconsumed pending packet.
    _lock.lock(); _pending=next; _lock.unlock()
    return true

func _transport_file() -> RDShaderFile:
    return Shader18

func _extra_transport_uniforms() -> Array[RDUniform]:
    var uniforms: Array[RDUniform]=super._extra_transport_uniforms()
    _factor_caps=_rd.storage_buffer_create(_count*4)
    allocation_bytes+=_count*4
    uniforms.append(_uniform(16,_factor_caps))
    return uniforms

func _render_callback(kind: int,_render_data: RenderData) -> void:
    if kind!=EFFECT_CALLBACK_TYPE_PRE_OPAQUE or _count==0: return
    if profile_enabled and gpu_ready: _collect_profile()
    _lock.lock(); var data: Dictionary=_pending; _pending={}; _lock.unlock()
    if data.is_empty(): return
    var started: int=Time.get_ticks_usec()
    var initial: bool=not gpu_ready
    var bytes_uploaded: int=0
    var graph_changed: bool=initial or diagnostic_force_graph or data["geometry"]!=_resident_geometry or data[9]!=_resident_inputs.get(9) or data[11]!=_resident_inputs.get(11)
    var serial: int=frame_count+1
    if profile_enabled and not initial: _rd.capture_timestamp("lie18|%d|begin" % serial)
    if initial:
        # The matrix is zero-initialized exactly once, then stays GPU-resident.
        var zeros:=PackedByteArray(); zeros.resize(_count*_count*4)
        data[2]=zeros; _instance_bytes=data["instance"]
        if not _initialize_gpu(data): return
        bytes_uploaded+=zeros.size()
        if profile_enabled: _rd.capture_timestamp("lie18|%d|begin" % serial)
    for key in data:
        if key is int:
            var bytes: PackedByteArray=data[key]
            if key==2: continue
            if initial or bytes!=_resident_inputs.get(key):
                if not initial: _rd.buffer_update(_buffers[key-1 if key>=11 else key],0,bytes.size(),bytes)
                bytes_uploaded+=bytes.size(); _resident_inputs[key]=bytes
    var instances: PackedByteArray=data["instance"]
    if initial or instances!=_resident_inputs.get("instance"):
        if not initial: _rd.buffer_update(instance_rid,0,instances.size(),instances)
        bytes_uploaded+=instances.size(); _resident_inputs["instance"]=instances
    _light_count=int(data["lights"]); _bounces=int(data["bounces"])
    if profile_enabled: _rd.capture_timestamp("lie18|%d|graph_begin" % serial)
    var commands: int
    if graph_changed:
        commands=_rd.compute_list_begin()
        _rd.compute_list_bind_compute_pipeline(commands,_pipeline)
        _rd.compute_list_bind_uniform_set(commands,_set,0)
        _dispatch(commands,6,_count*_count); _dispatch(commands,7,_count); _dispatch(commands,8,_count*_count)
        _rd.compute_list_end()
        graph_rebuilds+=1
    else: _graph_reuses+=1
    if profile_enabled: _rd.capture_timestamp("lie18|%d|graph_end" % serial)
    commands=_rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(commands,_pipeline)
    _rd.compute_list_bind_uniform_set(commands,_set,0)
    _dispatch(commands,0,_count*_light_count); _dispatch(commands,1,_light_count); _dispatch(commands,2,_count)
    for generation in range(_bounces): _dispatch(commands,3,_count,generation%2)
    _dispatch(commands,4,_count); _rd.compute_list_end()
    if profile_enabled: _rd.capture_timestamp("lie18|%d|end" % serial)
    render_poses.assign(data["poses"]); render_slots=data["slots"].duplicate(); render_signature=data["signature"]
    _resident_geometry=data["geometry"]; _upload_bytes+=bytes_uploaded; frame_count+=1
    var row: Dictionary={"serial":serial,"graph_rebuilt":graph_changed,"upload_bytes":bytes_uploaded,"dispatches":4+_bounces+(3 if graph_changed else 0),"cpu_pack_us":data["cpu_pack_us"],"cpu_submit_us":Time.get_ticks_usec()-started}
    if profile_enabled:
        _profile_meta[serial]=row
        if _profile_meta.size()>180: _profile_meta.erase(_profile_meta.keys()[0])
    _lock.lock()
    _metrics={"transport_solves":frame_count,"graph_rebuilds":graph_rebuilds,"graph_reuses":_graph_reuses,"upload_bytes_total":_upload_bytes,"last_solve":row,"profile":_profile_rows.duplicate(true)}
    _lock.unlock()

func _collect_profile() -> void:
    var frame: int=_rd.get_captured_timestamps_frame()
    if frame==_last_profile_frame: return
    _last_profile_frame=frame
    var intervals: Dictionary={}
    for i in range(_rd.get_captured_timestamps_count()):
        var parts: PackedStringArray=_rd.get_captured_timestamp_name(i).split("|")
        if parts.size()!=3 or parts[0]!="lie18": continue
        var serial: int=int(parts[1])
        if not intervals.has(serial): intervals[serial]={}
        intervals[serial][parts[2]]=_rd.get_captured_timestamp_gpu_time(i)
    for serial in intervals:
        var stamps: Dictionary=intervals[serial]
        if not _profile_meta.has(serial) or not stamps.has_all(["begin","graph_begin","graph_end","end"]): continue
        var row: Dictionary=_profile_meta[serial].duplicate()
        # Preserve raw Vulkan nanoseconds (Godot 4.7.2 driver timestamp units).
        row["render_frame"]=frame
        row["transport_gpu_ns"]=maxi(0,stamps["end"]-stamps["begin"])
        row["graph_gpu_ns"]=maxi(0,stamps["graph_end"]-stamps["graph_begin"]) if row["graph_rebuilt"] else 0
        row["solve_gpu_ns"]=maxi(0,stamps["end"]-stamps["graph_end"])
        _profile_rows.append(row); _profile_meta.erase(serial)
        if _profile_rows.size()>180: _profile_rows.pop_front()
    _lock.lock(); _metrics["profile"]=_profile_rows.duplicate(true); _lock.unlock()

func metrics() -> Dictionary:
    _lock.lock(); var result: Dictionary=_metrics.duplicate(true); _lock.unlock()
    return result

func _capture_data() -> void:
    super._capture_data()
    if not gpu_ready: return
    var factors: PackedFloat32Array=_rd.buffer_get_data(_buffers[2]).to_float32_array()
    _lock.lock(); _readback["form_factors"]=factors; _readback["graph_rebuilds"]=graph_rebuilds; _readback["metrics"]=_metrics.duplicate(true); _lock.unlock()

func _release_gpu() -> void:
    super._release_gpu()
    if _factor_caps.is_valid(): _rd.free_rid(_factor_caps)
