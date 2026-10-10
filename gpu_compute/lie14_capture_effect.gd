extends CompositorEffect
## One immutable master buffer, articulated instances, camera-facing reconstruction.
const Rigid=preload("res://lie14_model.gd")
const PipelineFile: RDShaderFile=preload("res://shaders/lie14_pipeline.glsl")
const CompositeFile: RDShaderFile=preload("res://shaders/lie12_composite.glsl")
const ROOT: String="res://captures/rigid_master/"
const SIZE: int=384
const ROOM_SIDE: int=128
const MAX_TASKS: int=64
const TASK_STRIDE: int=ROOM_SIDE*ROOM_SIDE
var lighting: CompositorEffect
var master: Dictionary={}
var capture_loaded: bool=false
var gpu_ready: bool=false
var failure: String=""
var frame_count: int=0
var asset_upload_count: int=0
var allocation_bytes: int=0
var active_view_tasks: int=0
var visible_instances: int=0
var samples:=PackedFloat32Array()
var _poses: Array[Transform3D]=[]
var detailed_normals: bool=true
var _mutex:=Mutex.new()
var _probe_readback: Dictionary={}
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _composite_shader: RID
var _composite_pipeline: RID
var _set: RID
var _output: RID
var _sampler: RID
var _buffers: Array[RID]=[]

func _init() -> void:
    effect_callback_type=EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
    access_resolved_color=true
    access_resolved_depth=true
    _load_master()

func _load_master() -> void:
    if not FileAccess.file_exists(ROOT+"master.json"): return
    var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"master.json"))
    if not parsed is Dictionary: return
    master=parsed
    if int(master.get("schema",0))!=1 or master.get("normal_space","")!="object-local Lie XYZ": return
    var file: FileAccess=FileAccess.open(ROOT+"master-samples.bin",FileAccess.READ)
    var count: int=int(master.get("sample_count",0))
    if file==null or count<10000 or file.get_length()!=count*32: return
    if FileAccess.get_sha256(ROOT+"master-samples.bin")!=str(master["sample_sha256"]): return
    samples=file.get_buffer(file.get_length()).to_float32_array()
    for view in master["views"]:
        if int(view["start"])<0 or int(view["count"])<1 or int(view["count"])>TASK_STRIDE or int(view["start"])+int(view["count"])>count: return
    for i in range(count):
        var node: int=roundi(samples[i*8+7])
        var normal:=Vector3(samples[i*8+4],samples[i*8+5],samples[i*8+6])
        if node<0 or node>=18 or not normal.is_finite() or absf(normal.length_squared()-1)>.001: return
    capture_loaded=true

func set_poses(poses: Array[Transform3D]) -> void:
    _mutex.lock()
    _poses=poses.duplicate()
    _mutex.unlock()

func set_detailed_normals(value: bool) -> void:
    _mutex.lock()
    detailed_normals=value
    _mutex.unlock()

func _uniform(binding: int,rid: RID,is_image: bool=false) -> RDUniform:
    var u:=RDUniform.new()
    u.binding=binding
    u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if is_image else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    u.add_id(rid)
    return u

func _initialize_gpu() -> bool:
    if not capture_loaded or lighting==null or not bool(lighting.get("gpu_ready")): return false
    _rd=RenderingServer.get_rendering_device()
    if _rd==null: return false
    var code: RDShaderSPIRV=PipelineFile.get_spirv()
    var composite: RDShaderSPIRV=CompositeFile.get_spirv()
    failure=code.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)+composite.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
    if failure!="":
        push_error(failure)
        return false
    _shader=_rd.shader_create_from_spirv(code)
    _pipeline=_rd.compute_pipeline_create(_shader)
    _composite_shader=_rd.shader_create_from_spirv(composite)
    _composite_pipeline=_rd.compute_pipeline_create(_composite_shader)
    var camera_bytes:=PackedByteArray()
    camera_bytes.resize(96)
    var jobs:=PackedFloat32Array()
    jobs.resize(MAX_TASKS*4)
    var projected:=PackedFloat32Array()
    projected.resize(MAX_TASKS*TASK_STRIDE*4)
    var depths:=PackedInt32Array()
    depths.resize(SIZE*SIZE)
    var sums:=PackedInt32Array()
    sums.resize(SIZE*SIZE*4)
    var probes:=PackedInt32Array()
    for instance in range(3):
        for sample in master["probe_samples"]: probes.append_array(PackedInt32Array([int(sample),instance,0,0]))
    var probe_output:=PackedFloat32Array()
    probe_output.resize(probes.size()*2)
    var bytes: Array[PackedByteArray]=[samples.to_byte_array(),jobs.to_byte_array(),camera_bytes,
        projected.to_byte_array(),depths.to_byte_array(),sums.to_byte_array(),probes.to_byte_array(),probe_output.to_byte_array(),depths.to_byte_array()]
    var bindings: Array=[0,1,2,3,4,5,16,17,6]
    var uniforms: Array[RDUniform]=[]
    for i in range(bytes.size()):
        var rid: RID=_rd.storage_buffer_create(bytes[i].size(),bytes[i])
        _buffers.append(rid)
        uniforms.append(_uniform(int(bindings[i]),rid))
        allocation_bytes+=bytes[i].size()
    asset_upload_count+=1
    var format:=RDTextureFormat.new()
    format.width=SIZE
    format.height=SIZE
    format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
    _output=_rd.texture_create(format,RDTextureView.new(),[])
    allocation_bytes+=SIZE*SIZE*16
    uniforms.append(_uniform(7,_output,true))
    var producer: Array=lighting.get("_buffers")
    uniforms.append_array([_uniform(11,lighting.get("output_rid"),true),_uniform(12,producer[0]),
        _uniform(14,lighting.get("instance_rid")),_uniform(15,lighting.get("direct_rid"),true),
        _uniform(18,producer[1]),_uniform(19,producer[4])])
    _set=_rd.uniform_set_create(uniforms,_shader,0)
    var sampler:=RDSamplerState.new()
    sampler.min_filter=RenderingDevice.SAMPLER_FILTER_NEAREST
    sampler.mag_filter=RenderingDevice.SAMPLER_FILTER_NEAREST
    _sampler=_rd.sampler_create(sampler)
    gpu_ready=_set.is_valid() and _pipeline.is_valid() and _composite_pipeline.is_valid()
    return gpu_ready

func _jobs(poses: Array[Transform3D],eye: Transform3D,tan_y: float,aspect: float) -> PackedFloat32Array:
    var data:=PackedFloat32Array()
    visible_instances=0
    for instance in range(poses.size()):
        var pose: Transform3D=poses[instance]
        if not Rigid.box_visible(pose,eye,tan_y,aspect): continue
        visible_instances+=1
        var local_direction: Vector3=(pose.basis.transposed()*(eye.origin-pose.origin)).normalized()
        for view in master["views"]:
            var direction: Vector3=Rigid.Model.vector(view["direction"])
            var cosine: float=direction.dot(local_direction)
            # Compact angular support goes smoothly to zero at its boundary.
            # All supported views participate; no abrupt nearest-frame switch.
            var weight: float=pow(maxf(2*cosine-1,0),2)
            if weight>.00001: data.append_array(PackedFloat32Array([float(view["start"]),float(view["count"]),float(instance),weight]))
    return data

func _render_callback(kind: int,render_data: RenderData) -> void:
    if kind!=EFFECT_CALLBACK_TYPE_POST_TRANSPARENT: return
    var scene: RenderSceneData=render_data.get_render_scene_data()
    var buffers: RenderSceneBuffersRD=render_data.get_render_scene_buffers()
    if scene==null or buffers==null or buffers.get_view_count()!=1: return
    if not gpu_ready and not _initialize_gpu(): return
    var size: Vector2i=buffers.get_internal_size()
    var projection: Projection=scene.get_view_projection(0)
    var eye: Transform3D=scene.get_cam_transform()
    var tan_y: float=1/absf(projection[1].y)
    var aspect: float=absf(projection[1].y/projection[0].x)
    _mutex.lock()
    var poses: Array[Transform3D]=_poses.duplicate()
    var detail: bool=detailed_normals
    _mutex.unlock()
    var jobs: PackedFloat32Array=_jobs(poses,eye,tan_y,aspect)
    active_view_tasks=jobs.size()/4
    if active_view_tasks>MAX_TASKS:
        failure="LIE-14 perception task budget exceeded"
        push_error(failure)
        return
    _rd.buffer_update(_buffers[1],0,jobs.size()*4,jobs.to_byte_array())
    var camera:=PackedFloat32Array()
    for v in [eye.origin,eye.basis.x,eye.basis.y,-eye.basis.z]: camera.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    camera.append_array(PackedFloat32Array([tan_y,aspect,.1,100]))
    var camera_bytes: PackedByteArray=camera.to_byte_array()
    camera_bytes.append_array(PackedInt32Array([SIZE,SIZE,int(lighting.get("_light_count")),1 if detail else 0]).to_byte_array())
    _rd.buffer_update(_buffers[2],0,camera_bytes.size(),camera_bytes)
    var commands: int=_rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(commands,_pipeline)
    _rd.compute_list_bind_uniform_set(commands,_set,0)
    for stage in [0,1,2,6,3,7,4,5]:
        var push:=PackedInt32Array([stage,active_view_tasks,TASK_STRIDE,6]).to_byte_array()
        _rd.compute_list_set_push_constant(commands,push,16)
        var count: int=6 if stage==5 else SIZE*SIZE if stage==0 or stage==4 or stage>=6 else active_view_tasks*TASK_STRIDE
        _rd.compute_list_dispatch(commands,int(ceil(float(count)/64)),1,1)
        _rd.compute_list_add_barrier(commands)
    _rd.compute_list_bind_compute_pipeline(commands,_composite_pipeline)
    var depth:=RDUniform.new()
    depth.binding=2
    depth.uniform_type=RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
    depth.add_id(_sampler)
    depth.add_id(buffers.get_depth_layer(0))
    var screen_set: RID=UniformSetCacheRD.get_cache(_composite_shader,0,[_uniform(0,buffers.get_color_layer(0),true),
        _uniform(1,_output,true),depth,_uniform(3,_buffers[4])])
    _rd.compute_list_bind_uniform_set(commands,screen_set,0)
    var push:=PackedInt32Array([size.x,size.y,SIZE,SIZE]).to_byte_array()
    push.append_array(PackedFloat32Array([projection[2].z,projection[3].z,projection[2].w,projection[3].w]).to_byte_array())
    _rd.compute_list_set_push_constant(commands,push,push.size())
    _rd.compute_list_dispatch(commands,int(ceil(float(size.x)/8)),int(ceil(float(size.y)/8)),1)
    _rd.compute_list_end()
    frame_count+=1

func request_readback() -> void:
    _mutex.lock()
    _probe_readback={}
    _mutex.unlock()
    RenderingServer.call_on_render_thread(Callable(self,"_capture_data"))

func _capture_data() -> void:
    if not gpu_ready: return
    var probes: PackedFloat32Array=_rd.buffer_get_data(_buffers[7]).to_float32_array()
    var depth: PackedInt32Array=_rd.buffer_get_data(_buffers[4]).to_int32_array()
    var color: PackedFloat32Array=_rd.texture_get_data(_output,0).to_float32_array()
    var owners: PackedInt32Array=_rd.buffer_get_data(_buffers[8]).to_int32_array()
    _mutex.lock()
    _probe_readback={"probes":probes,"depth":depth,"color":color,"owners":owners,"frames":frame_count,
        "allocation_bytes":allocation_bytes,"asset_uploads":asset_upload_count,
        "active_view_tasks":active_view_tasks,"visible_instances":visible_instances}
    _mutex.unlock()

func readback() -> Dictionary:
    _mutex.lock()
    var result: Dictionary=_probe_readback.duplicate()
    _mutex.unlock()
    return result

func shutdown() -> void:
    enabled=false
    if _rd!=null: RenderingServer.call_on_render_thread(Callable(self,"_release_gpu"))

func _release_gpu() -> void:
    if _rd==null: return
    if _set.is_valid(): _rd.free_rid(_set)
    for rid in _buffers:
        if rid.is_valid(): _rd.free_rid(rid)
    for rid in [_output,_pipeline,_shader,_composite_pipeline,_composite_shader,_sampler]:
        if rid.is_valid(): _rd.free_rid(rid)
    _buffers.clear()
    gpu_ready=false
