extends CompositorEffect
## Opaque depth merge -> four far-to-near dielectric sprite layers -> compose.
## Intermediate images are separate to avoid refractive feedback races.
const Codes=preload("res://lie13_optics_model.gd")
const OpticalShader: RDShaderFile=preload("res://shaders/lie13_optics.glsl")
const SIZE: int=256
var capture: CompositorEffect
var lighting: CompositorEffect
var gpu_ready: bool=false
var frame_count: int=0
var failure: String=""
var time_value: float=0.0
var environment_power: float=.65
var diagnostic_mode: int=0
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _sprites: RID
var _config: RID
var _sampler: RID
var _atlas: RID
var _images: Array[RID]=[]
var _diagnostic: RID
var _pending: PackedByteArray
var _count: int=0
var _lock:=Mutex.new()
var _readback: Dictionary={}

func _init() -> void:
    effect_callback_type=EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
    access_resolved_color=true
    access_resolved_depth=true

func set_sprites(values: Array) -> bool:
    if not Codes.valid(values,64): return false
    _lock.lock()
    _pending=Codes.bytes(values,true)
    _count=values.size()
    _lock.unlock()
    return true

func uniform(binding: int, rid: RID, image: bool=false) -> RDUniform:
    var u:=RDUniform.new()
    u.binding=binding
    u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if image else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    u.add_id(rid)
    return u

func texture_uniform(binding: int, rid: RID) -> RDUniform:
    var u:=RDUniform.new()
    u.binding=binding
    u.uniform_type=RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
    u.add_id(_sampler)
    u.add_id(rid)
    return u

func image(width: int,height: int,data: PackedByteArray=PackedByteArray()) -> RID:
    var fmt:=RDTextureFormat.new()
    fmt.width=width
    fmt.height=height
    fmt.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    fmt.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
    return _rd.texture_create(fmt,RDTextureView.new(),[] if data.is_empty() else [data])

func _initialize_gpu() -> bool:
    if capture==null or lighting==null or not bool(capture.get("gpu_ready")): return false
    _rd=RenderingServer.get_rendering_device()
    if _rd==null: return false
    var spirv:=OpticalShader.get_spirv()
    failure=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
    if failure!="": push_error(failure); return false
    _shader=_rd.shader_create_from_spirv(spirv)
    _pipeline=_rd.compute_pipeline_create(_shader)
    _sprites=_rd.storage_buffer_create(64*80)
    _config=_rd.storage_buffer_create(112)
    _images=[image(SIZE,SIZE),image(SIZE,SIZE)]
    _diagnostic=image(SIZE,SIZE)
    var filter:=RDSamplerState.new()
    filter.min_filter=RenderingDevice.SAMPLER_FILTER_NEAREST
    filter.mag_filter=RenderingDevice.SAMPLER_FILTER_NEAREST
    _sampler=_rd.sampler_create(filter)
    var data:=PackedFloat32Array()
    # Three reusable neutral sprites: flat glass, water tile, curved droplet.
    # Normal XYZ + mask/relative thickness. No baked light or colored artwork.
    for y in range(32):
        for x in range(96):
            var kind: int=x/32
            var uv:=Vector2((float(x%32)+.5)/16-1,(float(y)+.5)/16-1)
            var n:=Vector3(0,0,1)
            var mask: float=1.0
            if kind==2:
                var r2: float=uv.length_squared()
                mask=sqrt(maxf(0,1-r2)) if r2<1 else 0.0
                n=Vector3(uv.x,uv.y,mask).normalized()
            data.append_array(PackedFloat32Array([n.x,n.y,n.z,mask]))
    _atlas=image(96,32,data.to_byte_array())
    gpu_ready=_pipeline.is_valid() and _atlas.is_valid() and _images[1].is_valid() and _diagnostic.is_valid()
    return gpu_ready

func _render_callback(kind: int, render_data: RenderData) -> void:
    if kind!=EFFECT_CALLBACK_TYPE_POST_TRANSPARENT: return
    if not gpu_ready and not _initialize_gpu(): return
    var scene: RenderSceneBuffersRD=render_data.get_render_scene_buffers()
    var view_data: RenderSceneData=render_data.get_render_scene_data()
    if scene==null or view_data==null: return
    # This laboratory is mono perspective. Reject unsupported multi-view instead
    # of silently feeding the first view's camera to other eyes.
    if scene.get_view_count()!=1: failure="LIE-13 requires a mono perspective view"; return
    var transform: Transform3D=view_data.get_cam_transform()
    var proj: Projection=view_data.get_view_projection(0)
    if absf(proj[2].w)<.5: failure="Orthographic optical view unsupported"; return
    _lock.lock()
    var pending: PackedByteArray=_pending
    _pending=PackedByteArray()
    var count: int=_count
    _lock.unlock()
    if not pending.is_empty(): _rd.buffer_update(_sprites,0,pending.size(),pending)
    var bytes:=PackedInt32Array([SIZE,SIZE,count,int(lighting.get("_light_count"))]).to_byte_array()
    var packed:=PackedFloat32Array()
    for v in [transform.origin,transform.basis.x,transform.basis.y,-transform.basis.z]:
        packed.append_array(PackedFloat32Array([v.x,v.y,v.z,float(diagnostic_mode) if packed.is_empty() else 0.0]))
    packed.append_array(PackedFloat32Array([1.0/proj[1].y,proj[1].y/proj[0].x,time_value,environment_power,
        proj[2].z,proj[3].z,proj[2].w,proj[3].w]))
    bytes.append_array(packed.to_byte_array())
    _rd.buffer_update(_config,0,bytes.size(),bytes)
    var screen: RID=scene.get_color_layer(0)
    var depth: RID=scene.get_depth_layer(0)
    var cb: Array=capture.get("_buffers")
    var lb: Array=lighting.get("_buffers")
    var commands: int=_rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(commands,_pipeline)
    var read: int=1
    var write: int=0
    # Copy opaque snapshot, peel four ranks, composite final image.
    for pass_index in range(6):
        var stage: int=0 if pass_index==0 else 2 if pass_index==5 else 1
        var rank: int=4-pass_index
        var set_rid: RID=UniformSetCacheRD.get_cache(_shader,0,[uniform(0,screen,true),uniform(1,_images[read],true),uniform(2,_images[write],true),
            texture_uniform(3,depth),uniform(4,cb[5]),uniform(5,capture.get("_output_texture"),true),uniform(6,_sprites),uniform(7,_config),
            uniform(8,lb[1]),uniform(9,_diagnostic,true),texture_uniform(10,_atlas)])
        _rd.compute_list_bind_uniform_set(commands,set_rid,0)
        var push:=PackedInt32Array([stage,rank,0,0]).to_byte_array()
        _rd.compute_list_set_push_constant(commands,push,16)
        var size: Vector2i=scene.get_internal_size() if stage==2 else Vector2i(SIZE,SIZE)
        _rd.compute_list_dispatch(commands,ceili(float(size.x)/8),ceili(float(size.y)/8),1)
        _rd.compute_list_add_barrier(commands)
        var temp: int=read
        read=write
        write=temp
    _rd.compute_list_end()
    frame_count+=1

func request_readback() -> void:
    _lock.lock()
    _readback={}
    _lock.unlock()
    RenderingServer.call_on_render_thread(Callable(self,"_read_gpu"))

func _read_gpu() -> void:
    if not gpu_ready: return
    var data: PackedFloat32Array=_rd.texture_get_data(_diagnostic,0).to_float32_array()
    _lock.lock()
    _readback={"coefficients":data,"size":SIZE,"device":_rd.get_device_name()}
    _lock.unlock()

func readback() -> Dictionary:
    _lock.lock()
    var data: Dictionary=_readback.duplicate()
    _lock.unlock()
    return data

func shutdown() -> void:
    enabled=false
    if _rd!=null: RenderingServer.call_on_render_thread(Callable(self,"_release_gpu"))

func _release_gpu() -> void:
    for rid in [_pipeline,_shader,_sprites,_config,_sampler,_atlas,_diagnostic]+_images:
        if rid.is_valid(): _rd.free_rid(rid)
    gpu_ready=false
