extends "res://lie22_modular_effect.gd"
## All banks rasterize into the same depth, ownership, accumulation and shadow buffers.
const Kernels=preload("res://lie_construction_scene_kernels.gd")
const Identity=preload("res://lie_asset_catalog.gd")
var manifest: Dictionary={}
var banks: Array=[]
var _sets: Dictionary={}
var _kernels: Dictionary={}
var _leases: Array=[]
var _params: Array=[]
var _normals: Array=[]
var _limits: Array=[]
var _dummy:=RID()
var _sources_ready: bool=false
var total_source_bytes: int=0
var _reverse_passes: bool=false
func scene_root() -> String:return "res://captures/hq_construction/"
func capture_root() -> String:return scene_root()+"banks/"+str(manifest.banks[0])+"/"
func sample_stride() -> int:return 80
func instance_capacity() -> int:return 2048
func work_capacity() -> int:return 3000000
func shader_resource() -> RDShaderFile:return Kernels.SHADERS[1]
func _init(size: int=960) -> void:
    var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(scene_root()+"manifest.json"))
    if not parsed is Dictionary or not parsed.get("banks") is Array or parsed.banks.is_empty() or parsed.banks.size()>16:failure="Scene manifest";return
    manifest=parsed
    for name in manifest.banks:
        if not name is String or not name.is_valid_identifier():failure="Bank path";return
    super._init(512);output_size=clampi(size,256,1024);render_size=output_size*2
    if not capture_loaded:return
    for i in range(manifest.banks.size()):
        var path: String=scene_root()+"banks/"+str(manifest.banks[i])+"/"
        var cat: Dictionary=catalog if i==0 else JSON.parse_string(FileAccess.get_file_as_string(path+"catalog.json"))
        if cat.get("stride")!=80 or cat.get("bytes",0)>64*1024*1024:failure="Bank ABI/size";capture_loaded=false;return
        var data: PackedByteArray=_samples if i==0 else FileAccess.get_file_as_bytes(path+"library.bin")
        if data.size()!=int(cat.sample_count)*80 or FileAccess.get_sha256(path+"library.bin")!=cat.sha256:failure="Bank hash";capture_loaded=false;return
        var checked: Dictionary=Identity.validate(JSON.parse_string(FileAccess.get_file_as_string(path+"asset-contract.json")),cat)
        if not checked.ok:failure="Bank contract";capture_loaded=false;return
        for value in data.to_float32_array():
            if not is_finite(value):failure="Nonfinite source";capture_loaded=false;return
        var optical: Dictionary=cat.get("optical_normal_sidecar",{});var normal_data:=PackedByteArray()
        if not optical.is_empty():
            normal_data=FileAccess.get_file_as_bytes(path+str(optical.file))
            if optical.get("schema")!="lie-optical-normal-sidecar/1" or optical.source_bank_sha256!=cat.sha256 or normal_data.size()!=int(cat.sample_count)*16 or FileAccess.get_sha256(path+str(optical.file))!=optical.sha256:failure="Optical sidecar identity";capture_loaded=false;return
            var values: PackedFloat32Array=normal_data.to_float32_array()
            for p in range(0,values.size(),4):
                var n:=Vector3(values[p],values[p+1],values[p+2])
                if not n.is_finite() or absf(n.length()-1)>.0002 or values[p+3] not in [0.,1.]:failure="Optical sidecar values";capture_loaded=false;return
        total_source_bytes+=data.size()+normal_data.size()
        if total_source_bytes>320*1024*1024:failure="Residency budget";capture_loaded=false;return
        banks.append({"name":manifest.banks[i],"catalog":cat,"bytes":data,"normals":normal_data,"optical":optical})
func _source_range_ok(instances: PackedByteArray,instance: int,start: int,count: int) -> bool:
    var bank: float=instances.decode_float(instance*96+68)
    return is_finite(bank) and bank==roundf(bank) and bank>=0 and bank<banks.size() and start+count<=int(banks[int(bank)].catalog.sample_count)
func _source_limits(cat: Dictionary) -> PackedByteArray:
    var intervals: Array=[]
    for name in cat.masters:
        var master: Dictionary=cat.masters[name];var size: Array=master.bounds_size;var center: Array=master.get("bounds_center",[0,0,0]);var low:=Vector3(center[0]-size[0]/2.,center[1]-size[1]/2.,center[2]-size[2]/2.);var high:=low+Vector3(size[0],size[1],size[2])
        if master.has("modifications"):
            var cut: Dictionary=master.modifications;var a: Array=cut.bounds_min;var b: Array=cut.bounds_max;var pivot: float=(a[0]+b[0])/2.;low=Vector3(a[0]-pivot,a[1],a[2]);high=Vector3(b[0]-pivot,b[1],b[2])
        for level in master.levels:intervals.append({"start":int(level.start),"end":int(level.start+level.count),"low":low,"high":high})
    intervals.sort_custom(func(a: Dictionary,b: Dictionary):return a.start<b.start)
    var data:=PackedByteArray()
    for item in intervals:
        data.append_array(PackedInt32Array([item.start,item.end,0,0]).to_byte_array());data.append_array(PackedFloat32Array([item.low.x,item.low.y,item.low.z,0,item.high.x,item.high.y,item.high.z,0]).to_byte_array())
    return data
func _make_set() -> void:
    for rid in _sets.values():
        if _rd.uniform_set_is_valid(rid):_rd.free_rid(rid)
    _sets.clear();_set=RID()
    if not _sources_ready:
        _dummy=_rd.storage_buffer_create(16,PackedFloat32Array([0,0,1,0]).to_byte_array());allocation_bytes+=16
        for i in range(banks.size()):
            var limits: PackedByteArray=_source_limits(banks[i].catalog);_limits.append(_rd.storage_buffer_create(limits.size(),limits));allocation_bytes+=limits.size()
            if i==0:_leases.append({"rid":_buffers[0]});_params.append(_buffers[6]);banks[i].bytes=_samples
            else:
                var lease: Dictionary=SharedSamples.acquire(_rd,banks[i].bytes,banks[i].catalog.sha256,80)
                if not lease.ok:failure="Source lease";return
                _leases.append(lease);banks[i].bytes=lease.cpu_data;allocation_bytes+=lease.bytes;asset_uploads+=int(lease.uploaded);sample_bank_bindings+=1
                _params.append(_rd.storage_buffer_create(256));allocation_bytes+=256
            if banks[i].normals.is_empty():_normals.append({"rid":_dummy})
            else:
                var lease: Dictionary=SharedSamples.acquire(_rd,banks[i].normals,banks[i].optical.sha256,16)
                if not lease.ok:failure="Optical lease";return
                _normals.append(lease);banks[i].normals=lease.cpu_data;allocation_bytes+=lease.bytes;asset_uploads+=int(lease.uploaded)
        _sources_ready=true
    if _kernels.is_empty():
        for stage in Kernels.SHADERS:
            var spirv: RDShaderSPIRV=Kernels.SHADERS[stage].get_spirv()
            if spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)!="":failure="Scene kernel compile";return
            var shader: RID=_shader if stage==1 else _rd.shader_create_from_spirv(spirv)
            var pipeline: RID=_pipeline if stage==1 else _rd.compute_pipeline_create(shader)
            _kernels[stage]={"shader":shader,"pipeline":pipeline}
    for bank in range(banks.size()):
        var handles: Dictionary=_buffers.duplicate();handles.merge(_images);handles[0]=_leases[bank].rid;handles[6]=_params[bank];handles[14]=_normals[bank].rid;handles[15]=_limits[bank]
        for stage in _kernels:
            var uniforms: Array[RDUniform]=[]
            for binding in Kernels.BINDINGS[stage]:uniforms.append(_uniform(binding,handles[binding],binding in [8,9,11,12]))
            var uniform_set: RID=_rd.uniform_set_create(uniforms,_kernels[stage].shader,0)
            if not uniform_set.is_valid():failure="Scene descriptors";return
            _sets[str(bank)+":"+str(stage)]=uniform_set
    _set=_sets["0:1"]
func _update_parameters(parameters: PackedByteArray) -> void:
    _reverse_passes=parameters.decode_float(216)>.5
    for i in range(banks.size()):
        var data: PackedByteArray=parameters.duplicate();data.encode_float(248,float(i));data.encode_float(252,parameters.decode_float(252) if not banks[i].normals.is_empty() else 0.)
        _rd.buffer_update(_params[i],0,256,data)
func _dispatch_stage(commands: int,count: int) -> void:
    var groups: int=int(ceil(float(count)/64));var x: int=mini(groups,32768)
    _rd.compute_list_dispatch(commands,x,int(ceil(float(groups)/x)),1)
func _record_stage(commands: int,stage: int,count: int) -> void:
    var order: Array=range(banks.size() if stage in [2,3] else 1)
    if _reverse_passes and stage in [2,3]:order.reverse()
    for i in order:
        _rd.compute_list_bind_compute_pipeline(commands,_kernels[stage].pipeline);_rd.compute_list_bind_uniform_set(commands,_sets[str(i)+":"+str(stage)],0)
        _rd.compute_list_set_push_constant(commands,PackedInt32Array([stage,2,0,0]).to_byte_array(),16);_dispatch_stage(commands,count);_rd.compute_list_add_barrier(commands)
func _capture() -> void:
    super._capture()
    if not gpu_ready:return
    var shadow: PackedByteArray=_rd.buffer_get_data(_buffers[13])
    _mutex.lock();_readback["library_bytes"]=total_source_bytes;_readback["exclusive_allocation_bytes"]=allocation_bytes-total_source_bytes;_readback["banks"]=banks.size();_readback["shadow"]=shadow;_mutex.unlock()
func _release() -> void:
    for rid in _sets.values():
        if rid!=_set and _rd.uniform_set_is_valid(rid):_rd.free_rid(rid)
    _sets.clear()
    for stage in _kernels:
        if stage!=1:_rd.free_rid(_kernels[stage].pipeline);_rd.free_rid(_kernels[stage].shader)
    _kernels.clear()
    for i in range(_leases.size()):
        if i>0:SharedSamples.release_handle(_rd,_leases[i]);_rd.free_rid(_params[i])
    for lease in _normals:
        if lease.has("key"):SharedSamples.release_handle(_rd,lease)
    for rid in _limits:_rd.free_rid(rid)
    _limits.clear()
    _leases.clear();_params.clear();_normals.clear()
    if _dummy.is_valid():_rd.free_rid(_dummy)
    _dummy=RID();_sources_ready=false;super._release()
