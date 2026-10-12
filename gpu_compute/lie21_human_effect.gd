# LIE-21: higher-density neutral captures, weighted material reconstruction
# and linear HDR supersampling. The original mesh remains invisible.
extends CompositorEffect
const ShaderFile: RDShaderFile=preload("res://shaders/lie21_human.glsl")
const ROOT: String="res://captures/human_quality/"
var master: Dictionary={}
var capture_loaded: bool=false
var gpu_ready: bool=false
var failure: String=""
var frame_count: int=0
var asset_uploads: int=0
var allocation_bytes: int=0
var render_size: int=1024
var output_size: int=512
var quality_scale: int=2
var capture_root: String=ROOT
var output_rid:=RID()
var _input: Array[PackedByteArray]=[]
var _rd: RenderingDevice
var _shader:=RID()
var _pipeline:=RID()
var _set:=RID()
var _buffers: Array[RID]=[]
var _images: Array[RID]=[]
var _mutex:=Mutex.new()
var _parameters:=PackedByteArray()
var _readback: Dictionary={}
var _profiles: Array=[]
var _profile_frame: int=-1
var _resident_parameters:=PackedByteArray()
var _include_projection: bool=false

func _init(size: int=512,scale: int=2,root_path: String=ROOT) -> void:
    capture_root=root_path
    output_size=clampi(size,128,768);quality_scale=clampi(scale,1,2)
    render_size=output_size*quality_scale
    effect_callback_type=EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
    _load_master()

func _load_master() -> void:
    var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(capture_root+"master.json")) if FileAccess.file_exists(capture_root+"master.json") else null
    if not parsed is Dictionary: failure="Prepara el maestro humano en Blender."; return
    master=parsed
    if master.get("schema")!=1 or int(master.get("sample_count",0)) not in range(1,1000001) or int(master.get("vertex_count",0)) not in range(3,200001) or int(master.get("triangle_count",0)) not in range(1,400001): failure="Maestro humano fuera de contrato"; return
    for pair in [["vertices.bin",48,"vertex_count"],["triangles.bin",16,"triangle_count"],["samples.bin",80,"sample_count"]]:
        var path: String=capture_root+str(pair[0]);var file:=FileAccess.open(path,FileAccess.READ)
        var metadata: Dictionary=master.get("buffers",{}).get(pair[0],{})
        if file==null or file.get_length()!=int(pair[1])*int(master[pair[2]]) or FileAccess.get_sha256(path)!=metadata.get("sha256"):
            failure="Integridad del maestro: "+str(pair[0]);_input.clear();return
        _input.append(file.get_buffer(file.get_length()))
    var indices: PackedInt32Array=_input[1].to_int32_array()
    for i in range(0,indices.size(),4):
        for axis in range(3):
            if indices[i+axis]<0 or indices[i+axis]>=int(master["vertex_count"]): failure="Índice de superficie inválido";return
    var samples: PackedFloat32Array=_input[2].to_float32_array()
    for i in range(0,samples.size(),20):
        for k in range(20):
            if not is_finite(samples[i+k]): failure="Muestra no finita";return
        if int(samples[i+3])<0 or int(samples[i+3])>=int(master["triangle_count"]) or absf(samples[i]+samples[i+1]+samples[i+2]-1)>.0002:
            failure="Asociación de captura inválida";return
    capture_loaded=true

func configure(parameters: PackedByteArray) -> void:
    _mutex.lock();_parameters=parameters.duplicate();_mutex.unlock()

func _uniform(binding: int,rid: RID,is_image: bool=false) -> RDUniform:
    var u:=RDUniform.new();u.binding=binding;u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if is_image else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.add_id(rid);return u

func _initialize() -> bool:
    _rd=RenderingServer.get_rendering_device()
    if _rd==null: failure="RenderingDevice no disponible";return false
    var spirv: RDShaderSPIRV=ShaderFile.get_spirv()
    if spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)!="": failure=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE);return false
    _shader=_rd.shader_create_from_spirv(spirv);_pipeline=_rd.compute_pipeline_create(_shader)
    var lengths: Array=[int(master["vertex_count"])*16,int(master["sample_count"])*96,render_size*render_size*4,render_size*render_size*4,240,512*512*4,render_size*render_size*32]
    for data in _input:
        _buffers.append(_rd.storage_buffer_create(data.size(),data));allocation_bytes+=data.size()
    asset_uploads+=1
    for length in lengths:
        var data:=PackedByteArray();data.resize(int(length));_buffers.append(_rd.storage_buffer_create(data.size(),data));allocation_bytes+=data.size()
    var uniforms: Array[RDUniform]=[]
    for i in range(8): uniforms.append(_uniform(i,_buffers[i]))
    for binding in range(8,13):
        var format:=RDTextureFormat.new();format.width=output_size if binding==12 else render_size;format.height=format.width;format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
        format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
        var rid: RID=_rd.texture_create(format,RDTextureView.new(),[]);_images.append(rid);uniforms.append(_uniform(binding,rid,true));allocation_bytes+=format.width*format.height*16
    output_rid=_images[4];uniforms.append(_uniform(13,_buffers[8]));uniforms.append(_uniform(14,_buffers[9]));_set=_rd.uniform_set_create(uniforms,_shader,0)
    gpu_ready=_set.is_valid() and _pipeline.is_valid();return gpu_ready

func _collect_profile() -> void:
    var frame: int=_rd.get_captured_timestamps_frame()
    if frame==_profile_frame: return
    _profile_frame=frame
    var begin: int=-1;var end: int=-1
    for i in range(_rd.get_captured_timestamps_count()):
        var name: String=_rd.get_captured_timestamp_name(i)
        if name=="lie21-begin": begin=_rd.get_captured_timestamp_gpu_time(i)
        elif name=="lie21-end": end=_rd.get_captured_timestamp_gpu_time(i)
    _mutex.lock()
    if end>begin and begin>=0: _profiles.append({"render_frame":frame,"gpu_ns":end-begin})
    if _profiles.size()>120: _profiles.pop_front()
    _mutex.unlock()

func _render_callback(_type: int,_render_data: RenderData) -> void:
    if not capture_loaded or (not gpu_ready and not _initialize()): return
    _mutex.lock();var packet: PackedByteArray=_parameters.duplicate();_mutex.unlock()
    if packet.size()!=240: return
    _collect_profile()
    # A still portrait stays GPU-resident. Compare the last consumed packet;
    # coalesced user/agent edits only render their final evaluated state.
    if packet==_resident_parameters: return
    _rd.buffer_update(_buffers[7],0,packet.size(),packet)
    _rd.capture_timestamp("lie21-begin")
    var list: int=_rd.compute_list_begin();_rd.compute_list_bind_compute_pipeline(list,_pipeline);_rd.compute_list_bind_uniform_set(list,_set,0)
    for stage in range(8):
        var count: int=int(master["vertex_count"]) if stage==0 else int(master["sample_count"]) if stage in [2,3] else maxi(render_size*render_size,512*512) if stage==1 else render_size*render_size
        _rd.compute_list_set_push_constant(list,PackedInt32Array([stage,quality_scale,0,0]).to_byte_array(),16)
        _rd.compute_list_dispatch(list,int(ceil(float(count)/64)),1,1);_rd.compute_list_add_barrier(list)
    _rd.compute_list_end();_rd.capture_timestamp("lie21-end");frame_count+=1;_resident_parameters=packet

func request_readback(full_projection: bool=false) -> void:
    _mutex.lock();_readback={};_include_projection=full_projection;_mutex.unlock();RenderingServer.call_on_render_thread(Callable(self,"_capture_data"))

func _capture_data() -> void:
    if not gpu_ready: return
    _mutex.lock();var full: bool=_include_projection;_mutex.unlock()
    var weights: Array=[]
    for offset in [-24,0,24]:
        var pixel: int=((render_size>>1)+offset)*render_size+(render_size>>1)
        weights.append(_rd.buffer_get_data(_buffers[9],pixel*32,32).to_int32_array()[3])
    var result: Dictionary={"projected":_rd.buffer_get_data(_buffers[4]).to_float32_array() if full else PackedFloat32Array(),
        "depth":_rd.buffer_get_data(_buffers[5]).to_int32_array(),"winners":_rd.buffer_get_data(_buffers[6]).to_int32_array(),
        "color":_rd.texture_get_data(output_rid,0).to_float32_array(),
        "output_size":output_size,"internal_size":render_size,"material_weight_probes":weights,"frames":frame_count,"asset_uploads":asset_uploads,"allocation_bytes":allocation_bytes,"device":_rd.get_device_name(),"profile":_profiles.duplicate()}
    _mutex.lock();_readback=result;_mutex.unlock()

func readback() -> Dictionary:
    _mutex.lock();var result: Dictionary=_readback.duplicate();_mutex.unlock();return result

func shutdown() -> void:
    enabled=false
    if _rd!=null: RenderingServer.call_on_render_thread(Callable(self,"_release"))

func _release() -> void:
    for rid in [_set]+_buffers+_images+[_pipeline,_shader]:
        if rid.is_valid(): _rd.free_rid(rid)
    _buffers.clear();_images.clear();gpu_ready=false
