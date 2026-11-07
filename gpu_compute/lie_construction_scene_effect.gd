extends "res://lie22_modular_effect.gd"
## Exact LOD residency; all banks still share visibility and shading targets.
const Kernels=preload("res://lie_construction_scene_kernels.gd")
const Pages=preload("res://lie_capture_pages.gd")
var manifest: Dictionary={}
var banks: Array=[]
var _sets: Dictionary={}
var _kernels: Dictionary={}
var _resident_banks: Dictionary={}
var _params: Array=[]
var _dummy:=RID()
var _dummy_limits:=RID()
var _sources_ready: bool=false
var total_source_bytes: int=0
var catalog_source_bytes: int=0
var page_io_bytes: int=0
var residency_changes: int=0
var _reverse_passes: bool=false
var _job_signature:=PackedByteArray()
var _translated_jobs:=PackedByteArray()
var _plan_signature: String=""
func scene_root() -> String:return "res://captures/hq_construction/"
func capture_root() -> String:return scene_root()+"banks/"+str(manifest.banks[0])+"/"
func sample_stride() -> int:return 80
func instance_capacity() -> int:return 2048
func work_capacity() -> int:return 3000000
func shader_resource() -> RDShaderFile:return Kernels.SHADERS[1]
func _projection_stride() -> int:return 80
func _projection_target(work: int) -> int:return mini(work_capacity(),maxi(65536,ceili(float(work)/65536)*65536))
func _image_bindings() -> Array:return [11,12]
func _run_stage(stage: int) -> bool:return stage!=6
func _init(size: int=960) -> void:
    super._init(512);output_size=clampi(size,256,1024);render_size=output_size*2
func _load_capture_data() -> void:
    var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(scene_root()+"manifest.json"))
    if not parsed is Dictionary or not parsed.get("banks") is Array or parsed.banks.is_empty() or parsed.banks.size()>16:failure="Scene manifest";return
    manifest=parsed
    for name in manifest.banks:
        if not name is String or not name.is_valid_identifier():failure="Bank path";return
        var bank: Dictionary=Pages.open_bank(scene_root()+"banks/"+name+"/",manifest.bank_bindings.get(name,{}))
        if bank.is_empty():failure="Capture page metadata: "+name;return
        bank.name=name;banks.append(bank);catalog_source_bytes+=int(bank.catalog.bytes)+int(bank.optical.get("bytes",0))
    catalog=banks[0].catalog;capture_loaded=true
func _acquire_primary_source() -> bool:
    # The base owns writable geometry resources; its primary source slot is a
    # tiny inert RID. Actual sources are leased only after validated jobs exist.
    var bytes:=PackedByteArray();bytes.resize(80);_buffers[0]=_rd.storage_buffer_create(80,bytes);_lengths[0]=80;allocation_bytes+=80
    return _buffers[0].is_valid()
func _source_range_ok(instances: PackedByteArray,instance: int,start: int,count: int) -> bool:
    var bank: float=instances.decode_float(instance*96+68)
    return is_finite(bank) and bank==roundf(bank) and bank>=0 and bank<banks.size() and banks[int(bank)].index.entries.has(Pages.range_key(start,count))
func _clear_sets() -> void:
    for rid in _sets.values():
        if _rd.uniform_set_is_valid(rid):_rd.free_rid(rid)
    _sets.clear();_set=RID()
func _make_set() -> void:
    _clear_sets()
    if not _sources_ready:
        _dummy=_rd.storage_buffer_create(16,PackedFloat32Array([0,0,1,0]).to_byte_array());var bytes:=PackedByteArray();bytes.resize(48);_dummy_limits=_rd.storage_buffer_create(48,bytes);allocation_bytes+=64
        for i in range(banks.size()):
            _params.append(_buffers[6] if i==0 else _rd.storage_buffer_create(256))
            if i>0:allocation_bytes+=256
        _sources_ready=true
    if _kernels.is_empty():
        for stage in [1,2,3,4,7]:
            var spirv: RDShaderSPIRV=Kernels.SHADERS[stage].get_spirv()
            if spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)!="":failure="Scene kernel compile";return
            var shader: RID=_shader if stage==1 else _rd.shader_create_from_spirv(spirv);var pipeline: RID=_pipeline if stage==1 else _rd.compute_pipeline_create(shader)
            _kernels[stage]={"shader":shader,"pipeline":pipeline}
    for stage in _kernels:
        var order: Array=_resident_banks.keys() if stage in [2,3] else [0]
        for bank in order:
            var handles: Dictionary=_buffers.duplicate();handles.merge(_images);handles[6]=_params[bank];handles[14]=_dummy;handles[15]=_dummy_limits
            if _resident_banks.has(bank):
                var row: Dictionary=_resident_banks[bank];handles[0]=row.core.rid;handles[14]=row.optical.rid if row.has("optical") else _dummy;handles[15]=row.limits
            var uniforms: Array[RDUniform]=[]
            for binding in Kernels.BINDINGS[stage]:uniforms.append(_uniform(binding,handles[binding],binding in [11,12]))
            var set_rid: RID=_rd.uniform_set_create(uniforms,_kernels[stage].shader,0)
            if not set_rid.is_valid():failure="Scene descriptors";return
            _sets[str(bank)+":"+str(stage)]=set_rid
    _set=_sets["0:1"]
func _release_bank(row: Dictionary) -> void:
    SharedSamples.release_handle(_rd,row.core)
    if row.has("optical"):SharedSamples.release_handle(_rd,row.optical)
    _rd.free_rid(row.limits);allocation_bytes-=int(row.bytes)+int(row.limit_bytes);total_source_bytes-=int(row.bytes)
func _prepare_frame(next: Dictionary) -> Dictionary:
    var jobs: PackedInt32Array=next.jobs.to_int32_array();var instances: PackedByteArray=next.instances;var plans: Dictionary={}
    for i in range(0,jobs.size(),4):
        var bank: int=int(instances.decode_float(jobs[i+2]*96+68));var key: String=Pages.range_key(jobs[i],jobs[i+1])
        if not plans.has(bank):plans[bank]={}
        plans[bank][key]=banks[bank].index.entries[key]
    var signature: String=JSON.stringify(plans)
    if signature!=_plan_signature:
        var replacement: Dictionary={};var acquired: Array=[]
        for bank in plans:
            var keys: Array=plans[bank].keys();keys.sort_custom(func(a: String,b: String):return int(plans[bank][a].start)<int(plans[bank][b].start))
            var bank_key: String=JSON.stringify(keys)
            if _resident_banks.has(bank) and _resident_banks[bank].key==bank_key:replacement[bank]=_resident_banks[bank];continue
            var core:=PackedByteArray();var optical:=PackedByteArray();var limits:=PackedByteArray();var offsets: Dictionary={}
            for key in keys:
                var page: Dictionary=plans[bank][key];var part: Dictionary=Pages.read_range(banks[bank],int(page.start),int(page.count))
                if part.is_empty():
                    failure="Capture page integrity: "+str(bank)+"/"+key
                    for row in acquired:_release_uncommitted(row)
                    return {}
                page_io_bytes+=int(part.io_bytes);var start: int=core.size()/80;offsets[key]=start;core.append_array(part.core);optical.append_array(part.optical)
                limits.append_array(PackedInt32Array([start,start+int(page.count),0,0]).to_byte_array());limits.append_array(PackedFloat32Array([page.low[0],page.low[1],page.low[2],0,page.high[0],page.high[1],page.high[2],0]).to_byte_array())
            var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(core);var lease: Dictionary=SharedSamples.acquire(_rd,core,hash.finish().hex_encode(),80)
            if not lease.ok:
                failure="Capture page lease"
                for item in acquired:_release_uncommitted(item)
                return {}
            var row: Dictionary={"key":bank_key,"core":lease,"offsets":offsets,"ranges":keys,"bytes":core.size()+optical.size(),"limit_bytes":limits.size(),"limit_count":keys.size(),"limits":_rd.storage_buffer_create(limits.size(),limits)}
            if not optical.is_empty():
                hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(optical);row.optical=SharedSamples.acquire(_rd,optical,hash.finish().hex_encode(),16)
                if not row.optical.ok:
                    _release_uncommitted(row)
                    for item in acquired:_release_uncommitted(item)
                    failure="Optical page lease";return {}
            acquired.append(row);replacement[bank]=row
        var bytes: int=0
        for row in replacement.values():bytes+=int(row.bytes)
        if bytes>320*1024*1024:
            for row in acquired:_release_uncommitted(row)
            failure="Resident page budget";return {}
        _clear_sets()
        for bank in _resident_banks:
            if not replacement.has(bank) or replacement[bank]!=_resident_banks[bank]:_release_bank(_resident_banks[bank])
        for row in acquired:
            allocation_bytes+=int(row.bytes)+int(row.limit_bytes);total_source_bytes+=int(row.bytes);asset_uploads+=int(row.core.uploaded)+(int(row.optical.uploaded) if row.has("optical") else 0);sample_bank_bindings+=1
        _resident_banks=replacement;_plan_signature=signature;residency_changes+=1;_make_set()
    var translated: PackedInt32Array=jobs.duplicate()
    for i in range(0,jobs.size(),4):
        var bank: int=int(instances.decode_float(jobs[i+2]*96+68));translated[i]=_resident_banks[bank].offsets[Pages.range_key(jobs[i],jobs[i+1])]
    var result: Dictionary=next.duplicate();result.jobs=translated.to_byte_array();failure="";return result
func _release_uncommitted(row: Dictionary) -> void:
    if row.get("core",{}).get("ok",false):SharedSamples.release_handle(_rd,row.core)
    if row.get("optical",{}).get("ok",false):SharedSamples.release_handle(_rd,row.optical)
    if row.get("limits",RID()).is_valid():_rd.free_rid(row.limits)
func _update_parameters(parameters: PackedByteArray) -> void:
    _reverse_passes=parameters.decode_float(216)>.5
    for i in range(banks.size()):
        var row: Dictionary=_resident_banks.get(i,{});var data: PackedByteArray=parameters.duplicate();data.encode_float(208,float(row.get("limit_count",0)));data.encode_float(248,float(i));data.encode_float(252,parameters.decode_float(252) if row.has("optical") else 0.)
        _rd.buffer_update(_params[i],0,256,data)
func _dispatch_stage(commands: int,count: int) -> void:
    var groups: int=ceili(float(count)/64);var x: int=mini(groups,32768);_rd.compute_list_dispatch(commands,x,ceili(float(groups)/x),1)
func _record_stage(commands: int,stage: int,count: int) -> void:
    var order: Array=_resident_banks.keys() if stage in [2,3] else [0];order.sort()
    if _reverse_passes and stage in [2,3]:order.reverse()
    for i in order:
        _rd.compute_list_bind_compute_pipeline(commands,_kernels[stage].pipeline);_rd.compute_list_bind_uniform_set(commands,_sets[str(i)+":"+str(stage)],0);_rd.compute_list_set_push_constant(commands,PackedInt32Array([stage,2,0,0]).to_byte_array(),16);_dispatch_stage(commands,count);_rd.compute_list_add_barrier(commands)
func _capture() -> void:
    super._capture()
    if not gpu_ready:return
    var shadow: PackedByteArray=_rd.buffer_get_data(_buffers[13])
    _mutex.lock();_readback["library_bytes"]=total_source_bytes;_readback["exclusive_allocation_bytes"]=allocation_bytes-total_source_bytes;_readback["banks"]=banks.size();_readback["shadow"]=shadow;_readback["resident_banks"]=_resident_banks.size();_readback["catalog_source_bytes"]=catalog_source_bytes;_readback["page_io_bytes"]=page_io_bytes;_readback["residency_changes"]=residency_changes;_readback["projection_capacity"]=projection_capacity;_mutex.unlock()
func _release() -> void:
    _clear_sets()
    for stage in _kernels:
        if stage!=1:_rd.free_rid(_kernels[stage].pipeline);_rd.free_rid(_kernels[stage].shader)
    _kernels.clear()
    for row in _resident_banks.values():_release_bank(row)
    _resident_banks.clear();total_source_bytes=0;_plan_signature=""
    for i in range(_params.size()):
        if i>0:_rd.free_rid(_params[i])
    _params.clear()
    for rid in [_dummy,_dummy_limits]:
        if rid.is_valid():_rd.free_rid(rid)
    _dummy=RID();_dummy_limits=RID();_sources_ready=false
    if _buffers.has(0) and _buffers[0].is_valid():_rd.free_rid(_buffers[0]);_buffers.erase(0)
    super._release()
