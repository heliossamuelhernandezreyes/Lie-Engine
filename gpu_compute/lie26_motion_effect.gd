# LIE-26: captured anatomical surfaces driven by a shared kinematic rig.
extends CompositorEffect
const ShaderFile: RDShaderFile=preload("res://shaders/lie26_motion.glsl")
const ROOT: String="res://captures/anatomy26/"
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
var _bone_packet:=PackedByteArray()
var _resident_bones:=PackedByteArray()
var _include_projection: bool=false

func _init(size: int=512,scale: int=2,root_path: String=ROOT) -> void:
    capture_root=root_path
    output_size=clampi(size,128,768);quality_scale=clampi(scale,1,2)
    render_size=output_size*quality_scale
    effect_callback_type=EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
    _load_master()

func _load_master() -> void:
    var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(capture_root+"master.json")) if FileAccess.file_exists(capture_root+"master.json") else null
    if not parsed is Dictionary:failure="Prepara las capturas articuladas en Blender.";return
    master=parsed
    var count: Variant=master.get("sample_count",0)
    if not (count is float or count is int) or not is_finite(float(count)) or count!=floorf(float(count)) or count<1 or count>6000000:
        failure="Cantidad anatómica inválida";return
    if master.get("schema")!=3 or master.get("kind")!="lie-anatomy26-articulated" or master.get("vertex_stride")!=96 or master.get("sample_stride")!=80 or master.get("invocation_count")!=count or master.get("vertex_count",0)<8 or master.get("triangle_count",0)<12 or master.get("vertex_count",0)>2000000 or master.get("triangle_count",0)>2000000:
        failure="Maestro anatómico fuera de contrato";return
    var layers: Variant=master.get("layers")
    if not layers is Array or layers.size()!=4:failure="Capas anatómicas incompletas";return
    var end: int=0
    for id in range(4):
        var layer: Variant=layers[id]
        if not layer is Dictionary or layer.get("id")!=id or layer.get("sample_offset")!=end or not (layer.get("sample_count") is float or layer.get("sample_count") is int) or not is_finite(float(layer["sample_count"])) or float(layer["sample_count"])!=floorf(float(layer["sample_count"])) or layer["sample_count"]<1:
            failure="Rango anatómico inválido";return
        end+=int(layer["sample_count"])
    if end!=int(count):failure="Rango anatómico incompleto";return
    for pair in [["vertices.bin",96,"vertex_count"],["triangles.bin",16,"triangle_count"],["samples.bin",80,"sample_count"]]:
        var path: String=capture_root+str(pair[0]);var file:=FileAccess.open(path,FileAccess.READ)
        var metadata: Dictionary=master.get("buffers",{}).get(pair[0],{})
        if file==null or file.get_length()!=int(pair[1])*int(master[pair[2]]) or FileAccess.get_sha256(path)!=metadata.get("sha256"):
            failure="Integridad del maestro: "+str(pair[0]);_input.clear();return
        _input.append(file.get_buffer(file.get_length()))
    var bones: Variant=master.get("bones")
    if not bones is Array or bones.size()!=15 or master.get("bone_count")!=15:failure="Rig anatómico inválido";return
    for bid in range(15):
        var bone: Variant=bones[bid]
        if not bone is Dictionary or bone.get("id")!=bid or not bone.get("parent") is float or bone["parent"]!=floorf(bone["parent"]) or bone["parent"]>=bid or bone["parent"]<-1 or (bid>0 and bone["parent"]<0):failure="Jerarquía inválida";return
        for field in ["pivot","end"]:
            var position: Variant=bone.get(field)
            if not position is Array or position.size()!=3:failure="Pivote inválido";return
            for component in position:
                if not (component is float or component is int) or not is_finite(float(component)) or absf(component)>4:failure="Pivote inválido";return
    var samples: PackedFloat32Array=_input[2].to_float32_array()
    for id in range(4):
        for j in range(int(layers[id]["sample_offset"]),int(layers[id]["sample_offset"]+layers[id]["sample_count"])):
            var i: int=j*20
            for k in range(20):
                if not is_finite(samples[i+k]):failure="Muestra no finita";return
            if samples[i+3]!=floorf(samples[i+3]) or samples[i+3]<-int(master["triangle_count"]) or samples[i+3]>=15 or samples[i+14]!=floorf(samples[i+14]) or samples[i+14]<0 or samples[i+14]>=15 or samples[i+13]<0 or samples[i+13]>1 or samples[i+15]!=id or samples[i+7]<=0 or absf(Vector3(samples[i+16],samples[i+17],samples[i+18]).length()-1)>.0002:
                failure="Asociación anatómica inválida";return
            if samples[i+3]<0 and (absf(samples[i]+samples[i+1]+samples[i+2]-1)>.0002 or minf(samples[i],minf(samples[i+1],samples[i+2]))<-.0001):failure="Coordenadas de junta inválidas";return
            if samples[i+3]>=0 and samples[i+13]>0 and samples[i+13]<1 and samples[i+3]!=samples[i+14] and master["bones"][int(samples[i+14])]["parent"]!=samples[i+3]:failure="Pesos entre huesos desconectados";return
    var vertex_data:=_input[0].to_float32_array();var triangle_data:=_input[1].to_int32_array()
    for i in range(int(master["vertex_count"])):
        for k in range(24):
            if not is_finite(vertex_data[i*24+k]):failure="Vértice de junta no finito";return
        if vertex_data[i*24+3]!=floorf(vertex_data[i*24+3]) or vertex_data[i*24+3]<0 or vertex_data[i*24+3]>=15 or vertex_data[i*24+4]!=floorf(vertex_data[i*24+4]) or vertex_data[i*24+4]<0 or vertex_data[i*24+4]>=15 or vertex_data[i*24+5]<0 or vertex_data[i*24+5]>1:failure="Vértice de junta inválido";return
    for i in range(int(master["triangle_count"])):
        for k in range(3):
            if triangle_data[i*4+k]<0 or triangle_data[i*4+k]>=int(master["vertex_count"]):failure="Triángulo de junta inválido";return
    capture_loaded=true

func configure(parameters: PackedByteArray,bone_packet: PackedByteArray) -> bool:
    if not capture_loaded or parameters.size()!=320 or parameters.decode_s32(96)!=int(master["sample_count"]) or parameters.decode_s32(100)!=int(master["vertex_count"]) or parameters.decode_s32(104)!=render_size or parameters.decode_s32(108)!=render_size:return false
    var values: PackedFloat32Array=parameters.to_float32_array()
    for i in range(values.size()):
        if i not in range(24,28) and not is_finite(values[i]):return false
    var mask: float=parameters.decode_float(120)
    if mask!=floorf(mask) or mask<0 or mask>15:return false
    for offset in [240,272,288,304]:
        for axis in range(3):
            var color: float=parameters.decode_float(offset+axis*4)
            if color<0 or color>1:return false
    if bone_packet.size()!=15*32:return false
    var bone_values:=bone_packet.to_float32_array()
    for v in bone_values:
        if not is_finite(v):return false
    for bid in range(15):
        var q:=Quaternion(bone_values[bid*8],bone_values[bid*8+1],bone_values[bid*8+2],bone_values[bid*8+3])
        var d:=Quaternion(bone_values[bid*8+4],bone_values[bid*8+5],bone_values[bid*8+6],bone_values[bid*8+7])
        if absf(q.length_squared()-1)>.0001 or absf(q.dot(d))>.0001:return false
    _mutex.lock();_parameters=parameters.duplicate();_bone_packet=bone_packet.duplicate();_mutex.unlock()
    return true

func _uniform(binding: int,rid: RID,is_image: bool=false) -> RDUniform:
    var u:=RDUniform.new();u.binding=binding;u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if is_image else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.add_id(rid);return u

func _initialize() -> bool:
    _rd=RenderingServer.get_rendering_device()
    if _rd==null: failure="RenderingDevice no disponible";return false
    var spirv: RDShaderSPIRV=ShaderFile.get_spirv()
    if spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)!="": failure=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE);return false
    _shader=_rd.shader_create_from_spirv(spirv);_pipeline=_rd.compute_pipeline_create(_shader)
    var lengths: Array=[int(master["vertex_count"])*32,int(master["invocation_count"])*96,render_size*render_size*4,render_size*render_size*4,320,1024*1024*4,render_size*render_size*32,15*32]
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
    output_rid=_images[4];uniforms.append(_uniform(13,_buffers[8]));uniforms.append(_uniform(14,_buffers[9]));uniforms.append(_uniform(15,_buffers[10]));_set=_rd.uniform_set_create(uniforms,_shader,0)
    gpu_ready=_set.is_valid() and _pipeline.is_valid();return gpu_ready

func _collect_profile() -> void:
    var frame: int=_rd.get_captured_timestamps_frame()
    if frame==_profile_frame: return
    _profile_frame=frame
    var begin: int=-1;var end: int=-1
    for i in range(_rd.get_captured_timestamps_count()):
        var name: String=_rd.get_captured_timestamp_name(i)
        if name=="lie26-begin": begin=_rd.get_captured_timestamp_gpu_time(i)
        elif name=="lie26-end": end=_rd.get_captured_timestamp_gpu_time(i)
    _mutex.lock()
    if end>begin and begin>=0: _profiles.append({"render_frame":frame,"gpu_ns":end-begin})
    if _profiles.size()>120: _profiles.pop_front()
    _mutex.unlock()

func _render_callback(_type: int,_render_data: RenderData) -> void:
    if not capture_loaded or (not gpu_ready and not _initialize()): return
    _mutex.lock();var packet: PackedByteArray=_parameters.duplicate();var bone_packet: PackedByteArray=_bone_packet.duplicate();_mutex.unlock()
    if packet.size()!=320 or bone_packet.size()!=15*32: return
    _collect_profile()
    # A still portrait stays GPU-resident. Compare the last consumed packet;
    # coalesced user/agent edits only render their final evaluated state.
    if packet==_resident_parameters and bone_packet==_resident_bones: return
    _rd.buffer_update(_buffers[7],0,packet.size(),packet)
    _rd.buffer_update(_buffers[10],0,bone_packet.size(),bone_packet)
    _rd.capture_timestamp("lie26-begin")
    var list: int=_rd.compute_list_begin();_rd.compute_list_bind_compute_pipeline(list,_pipeline);_rd.compute_list_bind_uniform_set(list,_set,0)
    for stage in [0,1,2,3,8,4,5,6,7]:
        var count: int=int(master["vertex_count"]) if stage==0 else int(master["invocation_count"]) if stage in [2,3,8] else maxi(render_size*render_size,1024*1024) if stage==1 else render_size*render_size
        _rd.compute_list_set_push_constant(list,PackedInt32Array([stage,quality_scale,0,0]).to_byte_array(),16)
        var groups: int=int(ceil(float(count)/64));var rows: int=int(ceil(float(groups)/65535))
        _rd.compute_list_dispatch(list,int(ceil(float(groups)/rows)),rows,1);_rd.compute_list_add_barrier(list)
    _rd.compute_list_end();_rd.capture_timestamp("lie26-end");frame_count+=1;_resident_parameters=packet;_resident_bones=bone_packet

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
