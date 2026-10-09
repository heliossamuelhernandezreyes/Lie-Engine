extends CompositorEffect
## Node light codes are solved in Vulkan before opaque Sprite3D rendering.
## Only input changes are uploaded; all bounce generations stay on the GPU.
const Model=preload("res://lie11_model.gd")
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

func _init() -> void:
    effect_callback_type=EFFECT_CALLBACK_TYPE_PRE_OPAQUE

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
    _count=count
    _triangle_count=triangle_count
    var dims:=PackedInt32Array([count,(model["lights"] as Array).size(),int(model.get("bounces",2)),(model.get("blockers",[]) as Array).size()])
    var config: PackedByteArray=dims.to_byte_array()
    config.append_array(PackedFloat32Array([0.0025,0.0,float((model.get("triangles",[]) as Array).size()),0.0]).to_byte_array())
    var next: Dictionary={0:Model.patch_bytes(model),1:Model.light_bytes(model),
        2:Model.factor_bytes(model),8:config,9:Model.blocker_bytes(model),11:Model.triangle_bytes(model)}
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
    if not Model.valid(model) or (model["lights"] as Array).size()!=_light_count:
        return
    var data: PackedByteArray=Model.light_bytes(model)
    _lock.lock()
    _pending[1]=data
    _lock.unlock()

func _uniform(binding: int, rid: RID, image: bool=false) -> RDUniform:
    var u:=RDUniform.new()
    u.binding=binding
    u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if image else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    u.add_id(rid)
    return u

func _initialize_gpu(data: Dictionary) -> bool:
    _rd=RenderingServer.get_rendering_device()
    if _rd==null:
        failure="LIE-11 requires a RenderingDevice renderer"
        return false
    var spirv:=TRANSPORT_SHADER.get_spirv()
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
        float_zeros.to_byte_array(),float_zeros.to_byte_array(),float_zeros.to_byte_array(),data[8],data[9],data[11]]
    var uniforms: Array[RDUniform]=[]
    for binding in range(initial.size()):
        var bytes: PackedByteArray=initial[binding]
        var rid: RID=_rd.storage_buffer_create(bytes.size(),bytes)
        if not rid.is_valid():
            failure="Unable to allocate LIE-11 code buffer"
            return false
        _buffers.append(rid)
        allocation_bytes+=bytes.size()
        uniforms.append(_uniform(11 if binding==10 else binding,rid))
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
    uniforms.append(_uniform(10,output_rid,true))
    _set=_rd.uniform_set_create(uniforms,_shader,0)
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
    _lock.lock()
    var data: Dictionary=_pending
    _pending={}
    _lock.unlock()
    if not gpu_ready:
        if data.is_empty() or not _initialize_gpu(data):
            return
    for key in data:
        if key is int:
            var bytes: PackedByteArray=data[key]
            _rd.buffer_update(_buffers[10 if key==11 else key],0,bytes.size(),bytes)
    if data.has("lights"):
        _light_count=int(data["lights"])
        _bounces=int(data["bounces"])
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
    frame_count+=1

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
    _lock.lock()
    _readback={"flux":flux,"irradiance":irradiance,"frames":frame_count,
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
    gpu_ready=false
