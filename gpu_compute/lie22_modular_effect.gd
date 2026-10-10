extends CompositorEffect
## Immutable neutral captures shared by all eye / masonry instances.
const ShaderFile=preload("res://shaders/lie22_modular.glsl")
const ROOT="res://captures/modular22/"
const MAX_INSTANCES=128
const MAX_WORK=750000
var catalog: Dictionary={}
var capture_loaded: bool=false
var gpu_ready: bool=false
var failure: String=""
var output_rid:=RID()
var render_size: int=768
var output_size: int=384
var allocation_bytes: int=0
var asset_uploads: int=0
var frame_count: int=0
var sample_invocations: int=0
var instance_count: int=0
var projection_capacity: int=0
var _rd: RenderingDevice
var _shader:=RID()
var _pipeline:=RID()
var _set:=RID()
var _buffers: Dictionary={}
var _images: Dictionary={}
var _lengths: Dictionary={}
var _samples:=PackedByteArray()
var _mutex:=Mutex.new()
var _pending: Dictionary={}
var _resident:=PackedByteArray()
var _readback: Dictionary={}
var _profiles: Array=[]
var _profile_frame: int=-1

func _init(size: int=384) -> void:
    output_size=clampi(size,128,512);render_size=output_size*2
    effect_callback_type=EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
    var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"catalog.json"))
    if not parsed is Dictionary or parsed.get("schema")!=1 or parsed.get("stride")!=48: failure="Prepara los maestros modulares en Blender";return
    catalog=parsed
    var file:=FileAccess.open(ROOT+"library.bin",FileAccess.READ)
    if file==null or file.get_length()!=int(catalog.get("sample_count",0))*48 or file.get_length()>64*1024*1024 or FileAccess.get_sha256(ROOT+"library.bin")!=catalog.get("sha256"): failure="Integridad de biblioteca";return
    _samples=file.get_buffer(file.get_length())
    var values: PackedFloat32Array=_samples.to_float32_array()
    for value in values:
        if not is_finite(value):failure="Captura no finita";return
    for master in catalog.get("masters",{}).values():
        if master.get("levels",[]).size()!=2:failure="Niveles inválidos";return
        for level in master["levels"]:
            if int(level["start"])<0 or int(level["count"])<1 or int(level["start"])+int(level["count"])>int(catalog["sample_count"]):failure="Rango de captura";return
    capture_loaded=true

func configure(parameters: PackedByteArray,instances: PackedByteArray,jobs: PackedByteArray,work: int) -> bool:
    if parameters.size()!=256 or instances.size()%96!=0 or instances.size()>MAX_INSTANCES*96 or jobs.size()%16!=0 or jobs.size()>MAX_INSTANCES*16 or work<1 or work>MAX_WORK:return false
    if instances.is_empty() or jobs.is_empty() or parameters.decode_s32(80)!=work or parameters.decode_s32(84)!=jobs.size()/16 or parameters.decode_s32(88)!=render_size or parameters.decode_s32(92)!=render_size:return false
    var entries: PackedInt32Array=jobs.to_int32_array();var prefix: int=0
    for i in range(0,entries.size(),4):
        if entries[i]<0 or entries[i+1]<1 or entries[i]+entries[i+1]>int(catalog.get("sample_count",0)) or entries[i+2]<0 or entries[i+2]>=instances.size()/96 or entries[i+3]!=prefix:return false
        prefix+=entries[i+1]
    if prefix!=work:return false
    _mutex.lock();_pending={"parameters":parameters.duplicate(),"instances":instances.duplicate(),"jobs":jobs.duplicate(),"work":work};_mutex.unlock();return true

func _uniform(binding: int,rid: RID,is_image: bool=false) -> RDUniform:
    var u:=RDUniform.new();u.binding=binding;u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if is_image else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.add_id(rid);return u

func _buffer(binding: int,length: int,data: PackedByteArray=PackedByteArray()) -> void:
    if data.is_empty():data.resize(length)
    _buffers[binding]=_rd.storage_buffer_create(length,data);_lengths[binding]=length;allocation_bytes+=length

func _make_set() -> void:
    if _set.is_valid():_rd.free_rid(_set)
    var uniforms: Array[RDUniform]=[]
    for binding in _buffers:uniforms.append(_uniform(binding,_buffers[binding]))
    for binding in _images:uniforms.append(_uniform(binding,_images[binding],true))
    _set=_rd.uniform_set_create(uniforms,_shader,0)

func _initialize() -> bool:
    _rd=RenderingServer.get_rendering_device()
    if _rd==null:failure="RenderingDevice no disponible";return false
    var spirv: RDShaderSPIRV=ShaderFile.get_spirv()
    if spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)!="":failure=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE);return false
    _shader=_rd.shader_create_from_spirv(spirv);_pipeline=_rd.compute_pipeline_create(_shader)
    _buffer(0,_samples.size(),_samples);asset_uploads+=1
    _buffer(1,MAX_INSTANCES*96);_buffer(2,MAX_INSTANCES*16)
    projection_capacity=65536;_buffer(3,projection_capacity*96)
    _buffer(4,render_size*render_size*4);_buffer(5,render_size*render_size*4)
    _buffer(6,256);_buffer(7,render_size*render_size*32);_buffer(13,512*512*4)
    for binding in [8,9,11,12]:
        var format:=RDTextureFormat.new();format.width=output_size if binding==12 else render_size;format.height=format.width;format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
        format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
        var rid: RID=_rd.texture_create(format,RDTextureView.new(),[]);_images[binding]=rid;allocation_bytes+=format.width*format.height*16
    output_rid=_images[12];_make_set();gpu_ready=_set.is_valid() and _pipeline.is_valid();return gpu_ready

func _collect_profile() -> void:
    var frame: int=_rd.get_captured_timestamps_frame()
    if frame==_profile_frame:return
    _profile_frame=frame
    var begin: int=-1;var end: int=-1
    for i in range(_rd.get_captured_timestamps_count()):
        if _rd.get_captured_timestamp_name(i)=="lie22-begin":begin=_rd.get_captured_timestamp_gpu_time(i)
        if _rd.get_captured_timestamp_name(i)=="lie22-end":end=_rd.get_captured_timestamp_gpu_time(i)
    if end>begin and begin>=0:
        _mutex.lock();_profiles.append({"gpu_ns":end-begin})
        if _profiles.size()>120:_profiles.pop_front()
        _mutex.unlock()

func _render_callback(_type: int,_data: RenderData) -> void:
    if not capture_loaded or (not gpu_ready and not _initialize()):return
    _mutex.lock();var next: Dictionary=_pending.duplicate();_mutex.unlock()
    if next.is_empty():return
    _collect_profile()
    var signature: PackedByteArray=next["parameters"].duplicate();signature.append_array(next["instances"]);signature.append_array(next["jobs"])
    if signature==_resident:return
    var work: int=next["work"]
    if work>projection_capacity:
        _rd.free_rid(_set);_set=RID()
        _rd.free_rid(_buffers[3]);allocation_bytes-=int(_lengths[3]);projection_capacity=mini(MAX_WORK,int(ceil(float(work)/65536))*65536)
        _buffer(3,projection_capacity*96);_make_set()
    _rd.buffer_update(_buffers[6],0,256,next["parameters"])
    _rd.buffer_update(_buffers[1],0,next["instances"].size(),next["instances"])
    _rd.buffer_update(_buffers[2],0,next["jobs"].size(),next["jobs"])
    _rd.capture_timestamp("lie22-begin")
    var list: int=_rd.compute_list_begin();_rd.compute_list_bind_compute_pipeline(list,_pipeline);_rd.compute_list_bind_uniform_set(list,_set,0)
    for stage in [1,2,3,4,6,7]:
        var count: int=work if stage in [2,3] else maxi(render_size*render_size,512*512) if stage==1 else output_size*output_size if stage==7 else render_size*render_size
        _rd.compute_list_set_push_constant(list,PackedInt32Array([stage,2,0,0]).to_byte_array(),16)
        _rd.compute_list_dispatch(list,int(ceil(float(count)/64)),1,1);_rd.compute_list_add_barrier(list)
    _rd.compute_list_end();_rd.capture_timestamp("lie22-end")
    _resident=signature;sample_invocations=work;instance_count=next["instances"].size()/96;frame_count+=1

func request_readback() -> void:
    _mutex.lock();_readback={};_mutex.unlock();RenderingServer.call_on_render_thread(Callable(self,"_capture"))
func _capture() -> void:
    if not gpu_ready:return
    var result: Dictionary={"color":_rd.texture_get_data(output_rid,0).to_float32_array(),"depth":_rd.buffer_get_data(_buffers[4]).to_int32_array(),
        "output_size":output_size,"internal_size":render_size,"asset_uploads":asset_uploads,"allocation_bytes":allocation_bytes,"frames":frame_count,"sample_invocations":sample_invocations,"instances":instance_count,"device":_rd.get_device_name(),"profile":_profiles.duplicate(),"library_bytes":_samples.size()}
    _mutex.lock();_readback=result;_mutex.unlock()
func readback() -> Dictionary:
    _mutex.lock();var result: Dictionary=_readback.duplicate();_mutex.unlock();return result
func shutdown() -> void:
    enabled=false
    if _rd!=null:RenderingServer.call_on_render_thread(Callable(self,"_release"))
func _release() -> void:
    for rid in [_set]+_buffers.values()+_images.values()+[_pipeline,_shader]:
        if rid.is_valid():_rd.free_rid(rid)
    _buffers.clear();_images.clear();gpu_ready=false
