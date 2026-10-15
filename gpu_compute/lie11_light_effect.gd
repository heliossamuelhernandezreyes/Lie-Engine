extends CompositorEffect
## Node light codes are solved in Vulkan before opaque Sprite3D rendering.
## Only input changes are uploaded; all bounce generations stay on the GPU.
const Model=preload("res://lie11_model.gd")
const Optics=preload("res://lie13_optics_model.gd")
const TRANSPORT_SHADER: RDShaderFile=preload("res://shaders/lie11_light_transport.glsl")

var gpu_ready: bool=false
var frame_count: int=0
var output_rid: RID
var failure: String=""
var allocation_bytes: int=0
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _set: RID
var _buffers: Array[RID]=[]
var _count: int=0
var _triangle_count: int=-1
var _light_count: int=0
var _bounces: int=2
var _serial: int=0
var _pending: Dictionary={}
var _readback: Dictionary={}
var _lock:=Mutex.new()
var cache_static_transport: bool=false
var profile_transport: bool=false
var _resident_transport: Dictionary={}
var _transport_uniforms: Array[RDUniform]=[]
var _factor_capacity: int=0
var _transport_cache_hits: int=0
var _transport_upload_bytes: int=0
var _transport_profiles: Array=[]
var _transport_last_profile_serial: int=0

func _init() -> void:
    effect_callback_type=EFFECT_CALLBACK_TYPE_PRE_OPAQUE

func factor_input_bytes(model: Dictionary) -> PackedByteArray:
    return Model.factor_bytes(model)

func invalidate_transport() -> void:
    _lock.lock();_pending["force"]=true;_lock.unlock()

func _additional_transport_data(_model: Dictionary) -> Dictionary:return {}
func _before_transport_update(_data: Dictionary) -> void:pass

func configure(model: Dictionary) -> bool:
    if not Model.valid(model):
        failure="Invalid LIE-11 spatial/material/light code"
        push_error(failure)
        return false
    var count: int=(model["patches"] as Array).size()
    var triangle_count: int=(model.get("triangles",[]) as Array).size()
    if _triangle_count!=-1 and triangle_count!=_triangle_count:
        failure="Triangle count change requires a new effect allocation"
        push_error(failure)
        return false
    if _count!=0 and count!=_count:
        failure="Patch count change requires a new effect allocation"
        push_error(failure)
        return false
    var factors: PackedByteArray=factor_input_bytes(model)
    if factors.is_empty():
        failure="Invalid transport factor packet"
        return false
    failure=""
    _count=count
    _triangle_count=triangle_count
    var dims:=PackedInt32Array([count,(model["lights"] as Array).size(),int(model.get("bounces",2)),(model.get("blockers",[]) as Array).size()])
    var config: PackedByteArray=dims.to_byte_array()
    var policy: Dictionary=model.get("secondary_radii",{})
    config.append_array(PackedFloat32Array([0.0025,0.0,float(triangle_count),Model.radius_mode(policy)]).to_byte_array())
    config.append_array(PackedFloat32Array([float(policy.get("radius_max",1)),float(policy.get("radius_decay",1)),Model.radius_reference(policy),float((model.get("optical_sheets",[]) as Array).size())]).to_byte_array())
    var next: Dictionary={0:Model.patch_bytes(model),1:Model.light_bytes(model),
        2:factors,8:config,9:Model.blocker_bytes(model),11:Model.triangle_bytes(model),12:Model.radius_bytes(model),13:Optics.bytes(model.get("optical_sheets",[]))}
    next.merge(_additional_transport_data(model),true)
    _lock.lock()
    _serial+=1
    next["serial"]=_serial
    next["lights"]=(model["lights"] as Array).size()
    next["bounces"]=int(model.get("bounces",2))
    _pending=next
    _lock.unlock()
    return true

func set_light_codes(model: Dictionary) -> void:
    # A moving light changes a small persistent buffer; the spatial graph is reused.
    if not Model.valid_light_codes(model.get("lights",[])):
        return
    var data: PackedByteArray=Model.light_bytes(model)
    _lock.lock()
    if model["lights"].size()!=int(_pending.get("lights",_light_count)):_lock.unlock();return
    _pending[1]=data
    _pending.merge(_additional_transport_data(model),true)
    _lock.unlock()

## LIE-WALL-01 bridge: share the existing GPU-resident material code buffer
## with the LIE33 consumer; no duplicate material or light transport algorithm.
func material_codes_rid() -> RID:
    return _buffers[0] if gpu_ready and _buffers.size()>0 else RID()

func set_material_codes(model: Dictionary) -> bool:
    # Same patch graph, only absorption/filter metadata changes. Form factors
    # stay immutable and are NOT recomputed when codes change.
    if not gpu_ready or not Model.valid(model) or model["patches"].size()!=_count:
        return false
    var data: PackedByteArray=Model.patch_bytes(model)
    _lock.lock()
    _pending[0]=data
    _lock.unlock()
    return true

func _uniform(binding: int, rid: RID, image: bool=false) -> RDUniform:
    var u:=RDUniform.new()
    u.binding=binding
    u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if image else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    u.add_id(rid)
    return u

func _transport_file() -> RDShaderFile:
    return TRANSPORT_SHADER

func _extra_transport_uniforms() -> Array[RDUniform]:
    return []

func _initial_transport_buffer(binding: int, bytes: PackedByteArray) -> PackedByteArray:
    # Specializations may reserve more frontier channels without copying the
    # renderer's allocation, cache, timestamp or RID-lifetime implementation.
    return bytes

func _initialize_gpu(data: Dictionary) -> bool:
    if _shader.is_valid() or not _buffers.is_empty():_release_gpu()
    _rd=RenderingServer.get_rendering_device()
    if _rd==null:
        failure="LIE-11 requires a RenderingDevice renderer"
        return false
    var spirv:=_transport_file().get_spirv()
    failure=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
    if failure!="":
        push_error(failure)
        return false
    _shader=_rd.shader_create_from_spirv(spirv)
    if not _shader.is_valid():
        failure="Unable to create LIE-11 shader"
        return false
    _pipeline=_rd.compute_pipeline_create(_shader)
    var float_zeros:=PackedFloat32Array()
    float_zeros.resize(_count*4)
    var weights:=PackedFloat32Array()
    weights.resize(_count*16)
    var caps:=PackedFloat32Array()
    caps.resize(16)
    var initial: Array[PackedByteArray]=[
        data[0],data[1],data[2],weights.to_byte_array(),caps.to_byte_array(),
        float_zeros.to_byte_array(),float_zeros.to_byte_array(),float_zeros.to_byte_array(),data[8],data[9],data[11],data[12],data[13]]
    _transport_uniforms=[]
    for binding in range(initial.size()):
        var bytes: PackedByteArray=_initial_transport_buffer(binding,initial[binding])
        var rid: RID=_rd.storage_buffer_create(bytes.size(),bytes)
        if not rid.is_valid():
            failure="Unable to allocate LIE-11 code buffer"
            return false
        _buffers.append(rid)
        allocation_bytes+=bytes.size()
        _transport_uniforms.append(_uniform(binding+1 if binding>=10 else binding,rid))
    _factor_capacity=data[2].size()
    var format:=RDTextureFormat.new()
    format.width=_count
    format.height=1
    format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
    output_rid=_rd.texture_create(format,RDTextureView.new(),[])
    if not output_rid.is_valid():
        failure="Unable to allocate LIE-11 irradiance texture"
        return false
    allocation_bytes+=_count*16
    _transport_uniforms.append(_uniform(10,output_rid,true))
    _transport_uniforms.append_array(_extra_transport_uniforms())
    _set=_rd.uniform_set_create(_transport_uniforms,_shader,0)
    gpu_ready=_set.is_valid() and _pipeline.is_valid()
    if not gpu_ready:
        failure="Invalid LIE-11 transport uniform set"
    return gpu_ready

func _dispatch(commands: int, stage: int, threads: int, ping: int=0) -> void:
    var push:=PackedInt32Array([stage,ping,0,0]).to_byte_array()
    _rd.compute_list_set_push_constant(commands,push,16)
    _rd.compute_list_dispatch(commands,int(ceil(float(threads)/64.0)),1,1)
    _rd.compute_list_add_barrier(commands)

func _render_callback(kind: int, _render_data: RenderData) -> void:
    if kind!=EFFECT_CALLBACK_TYPE_PRE_OPAQUE or _count==0:
        return
    if profile_transport and gpu_ready:_collect_transport_profile()
    _lock.lock()
    var data: Dictionary=_pending
    _pending={}
    _lock.unlock()
    var initial: bool=not gpu_ready
    if cache_static_transport and not initial and not bool(data.get("force",false)):
        var changed: bool=false
        for key in data:
            if key is int and data[key]!=_resident_transport.get(key):changed=true;break
        if not changed:
            _transport_cache_hits+=1
            return
    _before_transport_update(data)
    if not gpu_ready:
        if data.is_empty() or not _initialize_gpu(data):
            return
    for key in data:
        if key is int:
            var bytes: PackedByteArray=data[key]
            var index: int=key-1 if key>=11 else key
            if key==2 and bytes.size()>_factor_capacity:
                # A geometry edit can grow a sparse graph. Replace only F,
                # retain every other buffer and the published irradiance RID.
                _rd.free_rid(_set);_rd.free_rid(_buffers[2])
                _buffers[2]=_rd.storage_buffer_create(bytes.size(),bytes)
                allocation_bytes+=bytes.size()-_factor_capacity
                _factor_capacity=bytes.size()
                _transport_uniforms[2]=_uniform(2,_buffers[2])
                _set=_rd.uniform_set_create(_transport_uniforms,_shader,0)
                if not _set.is_valid():failure="Sparse graph resize failed";gpu_ready=false;return
            elif not initial and (not cache_static_transport or bytes!=_resident_transport.get(key)):
                _rd.buffer_update(_buffers[index],0,bytes.size(),bytes)
            if initial or not cache_static_transport or bytes!=_resident_transport.get(key):_transport_upload_bytes+=bytes.size()
            _resident_transport[key]=bytes
    if data.has("lights"):
        _light_count=int(data["lights"])
        _bounces=int(data["bounces"])
    if profile_transport:_rd.capture_timestamp("lie11|%d|%d|begin" % [get_instance_id(),frame_count+1])
    var commands: int=_rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(commands,_pipeline)
    _rd.compute_list_bind_uniform_set(commands,_set,0)
    _dispatch(commands,0,_count*_light_count)
    _dispatch(commands,1,_light_count)
    _dispatch(commands,2,_count)
    for generation in range(_bounces):
        _dispatch(commands,3,_count,generation%2)
    _dispatch(commands,4,_count)
    _rd.compute_list_end()
    if profile_transport:_rd.capture_timestamp("lie11|%d|%d|end" % [get_instance_id(),frame_count+1])
    frame_count+=1

func _collect_transport_profile() -> void:
    var frame: int=_rd.get_captured_timestamps_frame()
    var intervals: Dictionary={}
    for i in range(_rd.get_captured_timestamps_count()):
        var parts: PackedStringArray=_rd.get_captured_timestamp_name(i).split("|")
        if parts.size()!=4 or parts[0]!="lie11" or parts[1]!=str(get_instance_id()):continue
        var serial: int=int(parts[2])
        if not intervals.has(serial):intervals[serial]={}
        intervals[serial][parts[3]]=_rd.get_captured_timestamp_gpu_time(i)
    _lock.lock()
    for serial in intervals:
        var row: Dictionary=intervals[serial]
        if serial>_transport_last_profile_serial and row.has_all(["begin","end"]) and row["end"]>row["begin"]:
            _transport_profiles.append({"serial":serial,"marker_frame":frame,"gpu_ns":row["end"]-row["begin"]})
            _transport_last_profile_serial=serial
    if _transport_profiles.size()>180:_transport_profiles=_transport_profiles.slice(_transport_profiles.size()-180)
    _lock.unlock()

func transport_metrics() -> Dictionary:
    _lock.lock()
    var result: Dictionary={"solves":frame_count,"cache_hits":_transport_cache_hits,
        "factor_buffer_capacity_bytes":_factor_capacity,"input_upload_bytes":_transport_upload_bytes,
        "profile":_transport_profiles.duplicate(true),"cache_static_transport":cache_static_transport}
    _lock.unlock();return result

func request_readback() -> void:
    # Explicit diagnostic readback only; never used by the running renderer.
    _lock.lock()
    _readback={}
    _lock.unlock()
    RenderingServer.call_on_render_thread(Callable(self,"_capture_data"))

func _capture_data() -> void:
    if not gpu_ready:
        return
    var flux: PackedFloat32Array=_rd.buffer_get_data(_buffers[7]).to_float32_array()
    var irradiance: PackedFloat32Array=_rd.texture_get_data(output_rid,0).to_float32_array()
    var frontier: PackedFloat32Array=_rd.buffer_get_data(_buffers[5 if _bounces%2==0 else 6]).to_float32_array()
    _lock.lock()
    _readback={"flux":flux,"irradiance":irradiance,"frontier":frontier,"frames":frame_count,
        "allocation_bytes":allocation_bytes,"device":_rd.get_device_name()}
    _lock.unlock()

func readback() -> Dictionary:
    _lock.lock()
    var copy: Dictionary=_readback.duplicate()
    _lock.unlock()
    return copy

func diagnostic_reference_codes(values: Array) -> void:
    # Deliberate oracle substitution for acceptance only, never runtime lighting.
    if values.size()!=_count: return
    var data:=PackedFloat32Array()
    for row in values:
        data.append_array(PackedFloat32Array([float(row[0]),float(row[1]),float(row[2]),1.0]))
    RenderingServer.call_on_render_thread(Callable(self,"_write_reference_codes").bind(data.to_byte_array()))

func _write_reference_codes(data: PackedByteArray) -> void:
    if gpu_ready: _rd.texture_update(output_rid,0,data)

func shutdown() -> void:
    enabled=false
    if _rd!=null:
        RenderingServer.call_on_render_thread(Callable(self,"_release_gpu"))

func _release_gpu() -> void:
    if _rd==null:
        return
    if _set.is_valid(): _rd.free_rid(_set)
    for rid in _buffers:
        if rid.is_valid(): _rd.free_rid(rid)
    for rid in [_pipeline,_shader,output_rid]:
        if rid.is_valid(): _rd.free_rid(rid)
    _buffers.clear()
    _transport_uniforms.clear();_resident_transport.clear();_factor_capacity=0
    _set=RID();_pipeline=RID();_shader=RID();output_rid=RID();allocation_bytes=0
    gpu_ready=false
