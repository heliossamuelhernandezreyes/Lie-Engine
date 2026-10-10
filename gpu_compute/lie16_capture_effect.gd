extends CompositorEffect
## Conservative capture levels, surface-aware fusion and rigid temporal resolve.
const Rigid=preload("res://lie15_model.gd")
const PipelineFile: RDShaderFile=preload("res://shaders/lie16_pipeline.glsl")
const TemporalFile: RDShaderFile=preload("res://shaders/lie16_temporal.glsl")
const CompositeFile: RDShaderFile=preload("res://shaders/lie16_composite.glsl")
const ROOT: String="res://captures/robot_master/"
const MAX_TASKS: int=Rigid.PARTS*60*2
const TASK_FLOATS: int=20
var lighting: CompositorEffect
var master: Dictionary={}
var capture_loaded: bool=false
var gpu_ready: bool=false
var failure: String=""
var frame_count: int=0
var asset_upload_count: int=0
var allocation_bytes: int=0
var render_size: int=384
var active_view_tasks: int=0
var visible_instances: int=0
var sample_invocations: int=0
var projected_bytes: int=0
var detailed_normals: bool=true
var samples:=PackedFloat32Array()
var _footprints:=PackedByteArray()
var _poses: Array[Transform3D]=[]
var _mutex:=Mutex.new()
var _probe_readback: Dictionary={}
var _settings: Dictionary={"adaptive":true,"temporal":true,"spatial":true,"jitter":true}
var _reset_serial: int=0
var _seen_reset_serial: int=-1
var _lighting_signature: String=""
var _history_valid: bool=false
var _history_index: int=0
var _history_resets: int=0
var _previous_camera:=PackedByteArray()
var _previous_eye:=Transform3D()
var _previous_tan: float=0
var _previous_poses: Array[Transform3D]=[]
var _last_jitter:=Vector2.ZERO
var _render_signature: String=""
var _lod_counts:=PackedInt32Array([0,0,0])
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _composite_shader: RID
var _composite_pipeline: RID
var _temporal_shader: RID
var _temporal_pipeline: RID
var _set: RID
var _output: RID
var _shown_output: RID
var _history: Array[RID]=[]
var _temporal_sets: Array[RID]=[]
var _sampler: RID
var _buffers: Array[RID]=[]
var _projection_capacity: int=262144
var _projection_grows: int=0
var profile_enabled: bool=false
var _profile_rows: Array=[]
var _last_profile_frame: int=-1
var _prepare_us: int=0
var edge_aa_enabled: bool=false

func pipeline_file() -> RDShaderFile:
    return PipelineFile

func temporal_file() -> RDShaderFile:
    return TemporalFile

func instance_capacity() -> int:
    return Rigid.PARTS

func render_poses() -> Array[Transform3D]:
    return _poses.duplicate()

func render_signature() -> String:
    return ""

func probe_codes() -> PackedInt32Array:
    var probes:=PackedInt32Array()
    for instance in range(instance_capacity()):
        for sample in master["probe_samples"]: probes.append_array(PackedInt32Array([int(sample),instance,0,0]))
    return probes

func composite_file() -> RDShaderFile:
    return CompositeFile

func set_edge_aa(value: bool) -> void:
    _mutex.lock()
    edge_aa_enabled=value
    _mutex.unlock()

func _init(size: int=384) -> void:
    render_size=clampi(size,256,768)
    effect_callback_type=EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
    access_resolved_color=true
    access_resolved_depth=true
    _load_master()

func _load_master() -> void:
    if not FileAccess.file_exists(ROOT+"quality-master.json"): return
    var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"quality-master.json"))
    if not parsed is Dictionary: return
    master=parsed
    if int(master.get("quality_schema",0))!=1 or (master.get("levels",[]) as Array).size()!=3: return
    # One winning piece contributes at most the shared master's sample count.
    # 13-bit coverage must fit uint32 even if every sample collapses to a pixel.
    if int(master["sample_count"])>524287: failure="LIE16 coverage accumulation capacity exceeded"; return
    var file:=FileAccess.open(ROOT+"quality-samples.bin",FileAccess.READ)
    if file==null or file.get_length()!=int(master["sample_count"])*32: return
    if FileAccess.get_sha256(ROOT+"quality-samples.bin")!=str(master["sample_sha256"]): return
    samples=file.get_buffer(file.get_length()).to_float32_array()
    var fp:=FileAccess.open(ROOT+"quality-footprints.bin",FileAccess.READ)
    if fp==null or fp.get_length()!=int(master["sample_count"])*4: return
    if FileAccess.get_sha256(ROOT+"quality-footprints.bin")!=str(master["footprint_sha256"]): return
    _footprints=fp.get_buffer(fp.get_length())
    for level in master["levels"]:
        if (level as Array).size()!=60: return
        for view in level:
            if int(view["start"])<0 or int(view["count"])<1 or int(view["start"])+int(view["count"])>int(master["sample_count"]): return
    for i in range(int(master["sample_count"])):
        var n:=Vector3(samples[i*8+4],samples[i*8+5],samples[i*8+6])
        if not n.is_finite() or absf(n.length_squared()-1)>.001 or roundi(samples[i*8+7]) not in range(6): return
    capture_loaded=true

func set_poses(poses: Array[Transform3D]) -> void:
    _mutex.lock()
    _poses=poses.duplicate()
    _mutex.unlock()

func set_detailed_normals(value: bool) -> void:
    _mutex.lock()
    detailed_normals=value
    _reset_serial+=1
    _mutex.unlock()

func configure_quality(adaptive: bool=true,temporal: bool=true,spatial: bool=true,jitter: bool=true) -> void:
    var next: Dictionary={"adaptive":adaptive,"temporal":temporal,"spatial":spatial,"jitter":jitter}
    _mutex.lock()
    if next!=_settings: _settings=next; _reset_serial+=1
    _mutex.unlock()

func reset_history() -> void:
    _mutex.lock()
    _reset_serial+=1
    _mutex.unlock()

func set_lighting_signature(code: String) -> void:
    _mutex.lock()
    if code!=_lighting_signature: _lighting_signature=code; _reset_serial+=1
    _mutex.unlock()

func _uniform(binding: int,rid: RID,is_image: bool=false) -> RDUniform:
    var u:=RDUniform.new()
    u.binding=binding
    u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if is_image else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    u.add_id(rid)
    return u

func _image() -> RID:
    var format:=RDTextureFormat.new()
    format.width=render_size
    format.height=render_size
    format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
    allocation_bytes+=render_size*render_size*16
    return _rd.texture_create(format,RDTextureView.new(),[])

func _make_set() -> void:
    var bindings: Array=[0,1,2,3,4,5,16,17,6,20,21,22]
    var uniforms: Array[RDUniform]=[]
    for i in range(bindings.size()): uniforms.append(_uniform(int(bindings[i]),_buffers[i]))
    uniforms.append(_uniform(7,_output,true))
    var producer: Array=lighting.get("_buffers")
    uniforms.append_array([_uniform(11,lighting.get("output_rid"),true),_uniform(12,producer[0]),
        _uniform(14,lighting.get("instance_rid")),_uniform(15,lighting.get("direct_rid"),true),
        _uniform(18,producer[1]),_uniform(19,producer[4])])
    _set=_rd.uniform_set_create(uniforms,_shader,0)

func _initialize_gpu() -> bool:
    if not capture_loaded or lighting==null or not bool(lighting.get("gpu_ready")): return false
    _rd=RenderingServer.get_rendering_device()
    if _rd==null: return false
    var screen_code: RDShaderFile=composite_file()
    for code in [pipeline_file(),temporal_file(),screen_code]:
        failure+=code.get_spirv().get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
    if failure!="": push_error(failure); return false
    _shader=_rd.shader_create_from_spirv(pipeline_file().get_spirv())
    _pipeline=_rd.compute_pipeline_create(_shader)
    _temporal_shader=_rd.shader_create_from_spirv(temporal_file().get_spirv())
    _temporal_pipeline=_rd.compute_pipeline_create(_temporal_shader)
    _composite_shader=_rd.shader_create_from_spirv(screen_code.get_spirv())
    _composite_pipeline=_rd.compute_pipeline_create(_composite_shader)
    var camera_bytes:=PackedByteArray(); camera_bytes.resize(112)
    var jobs:=PackedFloat32Array(); jobs.resize(instance_capacity()*60*2*TASK_FLOATS)
    var projected:=PackedByteArray(); projected.resize(_projection_capacity*32)
    projected_bytes=projected.size()
    var depth:=PackedInt32Array(); depth.resize(render_size*render_size)
    var sums:=PackedInt32Array(); sums.resize(render_size*render_size*4)
    var probes: PackedInt32Array=probe_codes()
    var probe_output:=PackedFloat32Array(); probe_output.resize(probes.size()*2)
    var counters:=PackedInt32Array(); counters.resize(16)
    var previous_poses:=PackedByteArray(); previous_poses.resize(instance_capacity()*64)
    var meta:=PackedByteArray(); meta.resize(render_size*render_size*8)
    var bytes: Array[PackedByteArray]=[samples.to_byte_array(),jobs.to_byte_array(),camera_bytes,
        projected,depth.to_byte_array(),sums.to_byte_array(),probes.to_byte_array(),probe_output.to_byte_array(),
        depth.to_byte_array(),counters.to_byte_array(),_footprints,depth.to_byte_array(),camera_bytes,previous_poses,meta,meta]
    for data in bytes:
        _buffers.append(_rd.storage_buffer_create(data.size(),data))
        allocation_bytes+=data.size()
    asset_upload_count+=1
    _output=_image()
    _history=[_image(),_image()]
    _shown_output=_output
    _make_set()
    for ping in range(2):
        var next: int=1-ping
        var uniforms: Array[RDUniform]=[_uniform(0,_output,true),_uniform(1,_history[ping],true),_uniform(2,_history[next],true),
            _uniform(3,_buffers[4]),_uniform(4,_buffers[8]),_uniform(5,_buffers[14+ping]),_uniform(6,_buffers[14+next]),
            _uniform(7,_buffers[2]),_uniform(8,_buffers[12]),_uniform(9,lighting.get("instance_rid")),
            _uniform(10,_buffers[13]),_uniform(11,_buffers[9])]
        _temporal_sets.append(_rd.uniform_set_create(uniforms,_temporal_shader,0))
    var sampler:=RDSamplerState.new()
    sampler.min_filter=RenderingDevice.SAMPLER_FILTER_NEAREST
    sampler.mag_filter=RenderingDevice.SAMPLER_FILTER_NEAREST
    _sampler=_rd.sampler_create(sampler)
    gpu_ready=_set.is_valid() and _temporal_sets[0].is_valid() and _temporal_sets[1].is_valid()
    return gpu_ready

func _grow_projection(count: int) -> void:
    if count<=_projection_capacity: return
    while _projection_capacity<count: _projection_capacity*=2
    var data:=PackedByteArray(); data.resize(_projection_capacity*32)
    _rd.free_rid(_set)
    _rd.free_rid(_buffers[3])
    allocation_bytes-=projected_bytes
    projected_bytes=data.size()
    allocation_bytes+=projected_bytes
    _buffers[3]=_rd.storage_buffer_create(data.size(),data)
    _make_set()
    _projection_grows+=1

func _lod_weights(spacing: float) -> Vector3:
    if spacing<=.30: return Vector3(0,0,1)
    if spacing<.35:
        var t: float=smoothstep(.30,.35,spacing)
        return Vector3(0,t,1-t)
    if spacing<=.60: return Vector3(0,1,0)
    if spacing<.70:
        var t: float=smoothstep(.60,.70,spacing)
        return Vector3(t,1-t,0)
    return Vector3(1,0,0)

func _jobs(poses: Array[Transform3D],eye: Transform3D,tan_y: float,aspect: float,adaptive: bool) -> PackedFloat32Array:
    var data:=PackedFloat32Array()
    var work: int=0
    visible_instances=0
    _lod_counts=PackedInt32Array([0,0,0])
    for instance in range(poses.size()):
        var pose: Transform3D=poses[instance]
        if not Rigid.box_visible(pose,eye,tan_y,aspect): continue
        visible_instances+=1
        var local_direction: Vector3=(pose.basis.inverse()*(eye.origin-pose.origin)).normalized()
        var depth: float=(eye.basis.inverse()*(pose.origin-eye.origin)).z*-1
        var scale: float=maxf(pose.basis.x.length(),maxf(pose.basis.y.length(),pose.basis.z.length()))
        var radius: float=pose.basis.get_scale().length()*.5
        var spacing: float=float(master["pixel_size_local"])*scale*float(render_size)/(2*tan_y*maxf(depth-radius,.1))
        var weights: Vector3=_lod_weights(spacing) if adaptive else Vector3(1,0,0)
        for level in range(3):
            if weights[level]<.0001: continue
            for view in master["levels"][level]:
                var direction: Vector3=Rigid.Model.vector(view["direction"])
                var cosine: float=direction.dot(local_direction)
                var weight: float=pow(maxf(2*cosine-1,0),2)*weights[level]
                if weight<=.00001: continue
                var count: int=int(view["count"])
                data.append_array(PackedFloat32Array([float(view["start"]),float(count),float(instance),weight,float(work),float(work+count),float(level),0]))
                for axis in ["right","up","forward"]:
                    var v: Vector3=Rigid.Model.vector(view[axis])
                    data.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
                work+=count
                _lod_counts[level]+=count
    sample_invocations=work
    return data

func _halton(index: int,base: int) -> float:
    var result: float=0
    var factor: float=1
    while index>0:
        factor/=base
        result+=factor*float(index%base)
        index=int(index/base)
    return result

func _camera_bytes(eye: Transform3D,tan_y: float,aspect: float,detail: bool,jitter: Vector2) -> PackedByteArray:
    var camera:=PackedFloat32Array()
    for v in [eye.origin,eye.basis.x,eye.basis.y,-eye.basis.z]: camera.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    camera.append_array(PackedFloat32Array([tan_y,aspect,.1,100]))
    var result: PackedByteArray=camera.to_byte_array()
    result.append_array(PackedInt32Array([render_size,render_size,int(lighting.get("_light_count")),1 if detail else 0]).to_byte_array())
    result.append_array(PackedFloat32Array([jitter.x,jitter.y,float(master["sample_count"]),0]).to_byte_array())
    return result

func _pose_bytes(poses: Array[Transform3D]) -> PackedByteArray:
    var data:=PackedFloat32Array()
    for pose in poses:
        for v in [pose.basis.x,pose.basis.y,pose.basis.z,pose.origin]: data.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    return data.to_byte_array()

func _collect_profile() -> void:
    var frame: int=_rd.get_captured_timestamps_frame()
    if frame==_last_profile_frame: return
    _last_profile_frame=frame
    var begin: int=-1
    var end: int=-1
    for i in range(_rd.get_captured_timestamps_count()):
        var name: String=_rd.get_captured_timestamp_name(i)
        if name=="lie16-consumer-begin": begin=_rd.get_captured_timestamp_gpu_time(i)
        elif name=="lie16-consumer-end": end=_rd.get_captured_timestamp_gpu_time(i)
    # Godot 4.7.2 Vulkan returns timestampPeriod-scaled NANOSECONDS in
    # drivers/vulkan/rendering_device_driver_vulkan.cpp, despite the reference
    # page describing microseconds. Retain the raw interval for reproducibility.
    _mutex.lock()
    if begin>=0 and end>begin: _profile_rows.append({"render_frame":frame,"consumer_gpu_ms":float(end-begin)/1000000,"consumer_gpu_ns":end-begin,"cpu_prepare_us":_prepare_us})
    if _profile_rows.size()>180: _profile_rows.pop_front()
    _mutex.unlock()

func profiling_snapshot() -> Array:
    _mutex.lock(); var result: Array=_profile_rows.duplicate(true); _mutex.unlock()
    return result

func _render_callback(kind: int,render_data: RenderData) -> void:
    if kind!=EFFECT_CALLBACK_TYPE_POST_TRANSPARENT: return
    var scene: RenderSceneData=render_data.get_render_scene_data()
    var buffers: RenderSceneBuffersRD=render_data.get_render_scene_buffers()
    if scene==null or buffers==null or buffers.get_view_count()!=1: return
    if not gpu_ready and not _initialize_gpu(): return
    if profile_enabled: _collect_profile()
    var prepare_start: int=Time.get_ticks_usec()
    var size: Vector2i=buffers.get_internal_size()
    var projection: Projection=scene.get_view_projection(0)
    var eye: Transform3D=scene.get_cam_transform()
    var tan_y: float=1/absf(projection[1].y)
    var aspect: float=absf(projection[1].y/projection[0].x)
    _mutex.lock()
    var poses: Array[Transform3D]=render_poses()
    var detail: bool=detailed_normals
    var edges: bool=edge_aa_enabled
    var settings: Dictionary=_settings.duplicate()
    var reset_serial: int=_reset_serial
    _mutex.unlock()
    if poses.size()!=instance_capacity(): return
    var signature: String=render_signature()
    if signature!=_render_signature:
        _history_valid=false
        _render_signature=signature
        _history_resets+=1
        var probes: PackedInt32Array=probe_codes()
        _rd.buffer_update(_buffers[6],0,probes.size()*4,probes.to_byte_array())
    var cut: bool=_history_valid and (eye.origin.distance_to(_previous_eye.origin)>.75 or eye.basis.z.dot(_previous_eye.basis.z)<.9 or absf(tan_y-_previous_tan)>.01)
    if cut or reset_serial!=_seen_reset_serial:
        if _history_valid: _history_resets+=1
        _history_valid=false
        _seen_reset_serial=reset_serial
    var jitter:=Vector2.ZERO
    if bool(settings["temporal"]) and bool(settings["jitter"]): jitter=Vector2(_halton(frame_count%8+1,2)-.5,_halton(frame_count%8+1,3)-.5)*.6
    _last_jitter=jitter
    var jobs: PackedFloat32Array=_jobs(poses,eye,tan_y,aspect,bool(settings["adaptive"]))
    active_view_tasks=int(jobs.size()/TASK_FLOATS)
    if active_view_tasks>instance_capacity()*60*2: failure="LIE16 task budget exceeded"; push_error(failure); return
    _grow_projection(sample_invocations)
    if not jobs.is_empty(): _rd.buffer_update(_buffers[1],0,jobs.size()*4,jobs.to_byte_array())
    var current_camera: PackedByteArray=_camera_bytes(eye,tan_y,aspect,detail,jitter)
    _rd.buffer_update(_buffers[2],0,current_camera.size(),current_camera)
    var before_camera: PackedByteArray=_previous_camera if _history_valid else current_camera
    var before_poses: PackedByteArray=_pose_bytes(_previous_poses if _history_valid else poses)
    _rd.buffer_update(_buffers[12],0,before_camera.size(),before_camera)
    _rd.buffer_update(_buffers[13],0,before_poses.size(),before_poses)
    _prepare_us=Time.get_ticks_usec()-prepare_start
    if profile_enabled: _rd.capture_timestamp("lie16-consumer-begin")
    var commands: int=_rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(commands,_pipeline)
    _rd.compute_list_bind_uniform_set(commands,_set,0)
    for stage in [0,1,2,6,8,9,3,7,4,5]:
        var push:=PackedInt32Array([stage,active_view_tasks,1,instance_capacity()*6]).to_byte_array()
        _rd.compute_list_set_push_constant(commands,push,16)
        var count: int=instance_capacity()*6 if stage==5 else render_size*render_size if stage in [0,4,6,7] else sample_invocations
        if count<=0: continue
        _rd.compute_list_dispatch(commands,int(ceil(float(count)/64)),1,1)
        _rd.compute_list_add_barrier(commands)
    _rd.compute_list_bind_compute_pipeline(commands,_temporal_pipeline)
    _rd.compute_list_bind_uniform_set(commands,_temporal_sets[_history_index],0)
    var policy: PackedByteArray=PackedInt32Array([1 if _history_valid else 0,1 if settings["temporal"] else 0,0,0]).to_byte_array()
    policy.append_array(PackedFloat32Array([.7,0,0,0]).to_byte_array())
    _rd.compute_list_set_push_constant(commands,policy,32)
    _rd.compute_list_dispatch(commands,int(ceil(float(render_size)/8)),int(ceil(float(render_size)/8)),1)
    _rd.compute_list_add_barrier(commands)
    _history_index=1-_history_index
    _shown_output=_history[_history_index]
    _rd.compute_list_bind_compute_pipeline(commands,_composite_pipeline)
    var depth:=RDUniform.new()
    depth.binding=2
    depth.uniform_type=RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
    depth.add_id(_sampler); depth.add_id(buffers.get_depth_layer(0))
    var screen_set: RID=UniformSetCacheRD.get_cache(_composite_shader,0,[_uniform(0,buffers.get_color_layer(0),true),_uniform(1,_shown_output,true),depth,_uniform(3,_buffers[4])])
    _rd.compute_list_bind_uniform_set(commands,screen_set,0)
    var push: PackedByteArray=PackedInt32Array([size.x,size.y,render_size,render_size]).to_byte_array()
    push.append_array(PackedFloat32Array([projection[2].z,projection[3].z,projection[2].w,projection[3].w]).to_byte_array())
    push.append_array(PackedInt32Array([1 if settings["spatial"] else 0,1 if edges else 0,0,0]).to_byte_array())
    _rd.compute_list_set_push_constant(commands,push,48)
    _rd.compute_list_dispatch(commands,int(ceil(float(size.x)/8)),int(ceil(float(size.y)/8)),1)
    _rd.compute_list_end()
    if profile_enabled: _rd.capture_timestamp("lie16-consumer-end")
    _previous_camera=current_camera
    _previous_eye=eye
    _previous_tan=tan_y
    _previous_poses=poses
    _history_valid=true
    frame_count+=1

func request_readback() -> void:
    _mutex.lock(); _probe_readback={}; _mutex.unlock()
    RenderingServer.call_on_render_thread(Callable(self,"_capture_data"))

func _capture_data() -> void:
    if not gpu_ready: return
    var result: Dictionary={"probes":_rd.buffer_get_data(_buffers[7]).to_float32_array(),"depth":_rd.buffer_get_data(_buffers[4]).to_int32_array(),
        "color":_rd.texture_get_data(_shown_output,0).to_float32_array(),"raw_color":_rd.texture_get_data(_output,0).to_float32_array(),
        "owners":_rd.buffer_get_data(_buffers[8]).to_int32_array(),"frames":frame_count,"allocation_bytes":allocation_bytes,"asset_uploads":asset_upload_count,
        "active_view_tasks":active_view_tasks,"visible_instances":visible_instances,"sample_invocations":sample_invocations,"projected_bytes":projected_bytes,
        "counters":_rd.buffer_get_data(_buffers[9]).to_int32_array(),"lod_sample_counts":_lod_counts,"projection_grows":_projection_grows,
        "history_resets":_history_resets,"profile":_profile_rows.duplicate(),"jitter":[_last_jitter.x,_last_jitter.y],"render_size":render_size,"device":_rd.get_device_name()}
    _mutex.lock(); _probe_readback=result; _mutex.unlock()

func readback() -> Dictionary:
    _mutex.lock(); var result: Dictionary=_probe_readback.duplicate(); _mutex.unlock()
    return result

func shutdown() -> void:
    enabled=false
    if _rd!=null: RenderingServer.call_on_render_thread(Callable(self,"_release_gpu"))

func _release_gpu() -> void:
    if _rd==null: return
    for rid in [_set]+_temporal_sets:
        if rid.is_valid(): _rd.free_rid(rid)
    for rid in _buffers+_history+[_output,_pipeline,_shader,_temporal_pipeline,_temporal_shader,_composite_pipeline,_composite_shader,_sampler]:
        if rid.is_valid(): _rd.free_rid(rid)
    _buffers.clear(); _history.clear(); _temporal_sets.clear()
    gpu_ready=false
