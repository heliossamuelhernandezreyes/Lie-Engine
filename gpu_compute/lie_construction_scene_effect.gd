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
var _pending_field: Dictionary={}
var _field_context: Dictionary={}
var _field_receipt: Dictionary={}
var _field_bound: Dictionary={}
var _field_map:=RID()
var _field_map_bytes: int=0
var _field_map_stamp:=PackedByteArray()
var _field_dummy_patch:=RID()
var _field_dummy_light:=RID()
var _field_dummy_image:=RID()
var _diagnostic_snapshot: Dictionary={}
var _bank_jobs: Dictionary={}
var _bank_job_bytes: int=0
var _view_stamp:=PackedByteArray()
var _shadow_stamp:=PackedByteArray()
var _uploaded_geometry:=PackedByteArray()
var _validated_instances:=PackedByteArray()
var _validated_jobs:=PackedByteArray()
var _validated_work: int=0
var _frame_passes: Dictionary={}
var _pass_counts: Dictionary={}
var _reset_view: bool=true
var _reset_shadow: bool=true
const PASS_NAMES={1:"clear",8:"shadow",2:"projection_depth",3:"material_accumulation",4:"shading",7:"output"}

func configure(parameters: PackedByteArray,instances: PackedByteArray,jobs: PackedByteArray,work: int) -> bool:
    # Reuse validation only for byte-identical immutable geometry. Dimensions
    # and count fields still have to match this consumer on every transaction.
    if parameters.size()!=256:return false
    if parameters.decode_s32(80)!=work or parameters.decode_s32(84)!=jobs.size()/16 or parameters.decode_s32(88)!=render_size or parameters.decode_s32(92)!=render_size:return false
    if work>0 and work==_validated_work and instances==_validated_instances and jobs==_validated_jobs:
        _mutex.lock();_pending={"parameters":parameters.duplicate(),"instances":instances.duplicate(),"jobs":jobs.duplicate(),"work":work};_mutex.unlock();return true
    if not super.configure(parameters,instances,jobs,work):return false
    _validated_instances=instances.duplicate();_validated_jobs=jobs.duplicate();_validated_work=work;return true

func _collect_profile() -> void:
    if frame_count==0:return
    var frame: int=_rd.get_captured_timestamps_frame();var intervals: Dictionary={}
    for i in range(_rd.get_captured_timestamps_count()):
        var parts: PackedStringArray=_rd.get_captured_timestamp_name(i).split("|")
        if parts.size()!=4 or parts[0]!="lie22" or parts[1]!=str(get_instance_id()):continue
        var serial: int=int(parts[2])
        if not intervals.has(serial):intervals[serial]={}
        intervals[serial][parts[3]]=_rd.get_captured_timestamp_gpu_time(i)
    _mutex.lock()
    for serial in intervals:
        var row: Dictionary=intervals[serial]
        if serial<=_last_profile_serial or not row.has_all(["begin","end"]) or row.end<=row.begin:continue
        var passes: Dictionary={}
        for name in _frame_passes.get(serial,[]):
            var a: String=name+"_begin";var b: String=name+"_end"
            if row.has(a) and row.has(b) and row[b]>row[a]:passes[name]=row[b]-row[a]
        _profiles.append({"owner_instance_id":get_instance_id(),"serial":serial,"marker_frame":frame,"gpu_ns":row.end-row.begin,"passes_ns":passes,"executed_passes":_frame_passes.get(serial,[]).duplicate()})
        _last_profile_serial=serial
    if _profiles.size()>120:_profiles=_profiles.slice(_profiles.size()-120)
    for serial in _frame_passes.keys():
        if serial<frame_count-120:_frame_passes.erase(serial)
    _mutex.unlock()

func _render_callback(_type: int,_data: RenderData) -> void:
    if not capture_loaded or (not gpu_ready and not _initialize()):return
    _mutex.lock();var next: Dictionary=_pending.duplicate();_mutex.unlock()
    if next.is_empty():return
    _collect_profile()
    var signature: PackedByteArray=_frame_signature(next)
    if signature==_resident:return
    var work: int=next.work;var capacity: int=_projection_target(work)
    if capacity!=projection_capacity:
        _clear_sets();_rd.free_rid(_buffers[3]);allocation_bytes-=int(_lengths[3]);projection_capacity=capacity
        _buffer(3,projection_capacity*_projection_stride());_make_set();_view_stamp=PackedByteArray()
    next=_prepare_frame(next)
    if next.is_empty():return
    var geometry: PackedByteArray=next.instances.duplicate();geometry.append_array(next.jobs)
    var p: PackedByteArray=next.parameters
    var view: PackedByteArray=geometry.duplicate();view.append_array(p.slice(0,96));view.append_array(p.slice(208,256))
    var shadow: PackedByteArray=geometry.duplicate();shadow.append_array(p.slice(96,112));shadow.append_array(p.slice(160,208))
    # Reverse-bank diagnostics deliberately rerun both paths, so order tests
    # continue to exercise rasterization instead of accidentally testing a hit.
    view.append_array(p.slice(216,220));shadow.append_array(p.slice(216,220))
    _reset_view=view!=_view_stamp;_reset_shadow=shadow!=_shadow_stamp
    _update_parameters(p)
    if geometry!=_uploaded_geometry:
        _rd.buffer_update(_buffers[1],0,next.instances.size(),next.instances)
        _rd.buffer_update(_buffers[2],0,next.jobs.size(),next.jobs)
        _uploaded_geometry=geometry
    var stages: Array=[]
    if _reset_view or _reset_shadow:stages.append(1)
    if _reset_shadow:stages.append(8)
    if _reset_view:stages.append_array([2,3])
    stages.append_array([4,7])
    var names: Array=[];_rd.capture_timestamp(_profile_marker("begin"))
    for stage in stages:
        var name: String=PASS_NAMES[stage];names.append(name)
        _rd.capture_timestamp(_profile_marker(name+"_begin"))
        var commands: int=_rd.compute_list_begin()
        var count: int=work if stage in [2,3,8] else maxi(render_size*render_size,512*512) if stage==1 else output_size*output_size if stage==7 else render_size*render_size
        _record_stage(commands,stage,count);_rd.compute_list_end()
        _rd.capture_timestamp(_profile_marker(name+"_end"));_pass_counts[name]=int(_pass_counts.get(name,0))+1
    _rd.capture_timestamp(_profile_marker("end"));_frame_passes[frame_count+1]=names
    _resident=signature;_view_stamp=view;_shadow_stamp=shadow;sample_invocations=work;instance_count=next.instances.size()/96;frame_count+=1
func request_diagnostics() -> void:
    RenderingServer.call_on_render_thread(Callable(self,"_publish_diagnostics"))
func diagnostics() -> Dictionary:
    _mutex.lock();var result: Dictionary=_diagnostic_snapshot.duplicate(true);_mutex.unlock();return result
func _publish_diagnostics() -> void:
    if gpu_ready:_collect_profile()
    # Metadata and asynchronous timestamps only: no buffer/texture readback,
    # submit, fence wait or synthetic timing for an idle cached frame.
    var result: Dictionary={"ready":gpu_ready,"failure":failure,"frames":frame_count,"owner":get_instance_id(),
        "allocation_bytes":allocation_bytes,"source_bytes":total_source_bytes,
        "exclusive_bytes":allocation_bytes-total_source_bytes,"page_io_bytes":page_io_bytes,
        "asset_uploads":asset_uploads,"instances":instance_count,"samples":sample_invocations,
        "output_size":output_size,"internal_size":render_size,"field":{},
        "profile":_profiles.duplicate(true),"pass_counts":_pass_counts.duplicate(),"bank_dispatch_samples":{},"snapshot_usec":Time.get_ticks_usec()}
    for bank in _bank_jobs:result.bank_dispatch_samples[str(bank)]=_bank_jobs[bank].work
    if gpu_ready:result.device=_rd.get_device_name()
    for key in ["producer","epoch","solve","nodes","bytes"]:
        if _field_receipt.has(key):result.field[key]=_field_receipt[key]
    _mutex.lock();_diagnostic_snapshot=result;_mutex.unlock()
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
func clear_field() -> void:
    _mutex.lock();_pending_field={};_mutex.unlock()
func bind_field(transport: CompositorEffect,mapping: PackedByteArray,instances: PackedByteArray,identity: String,indirect: bool=true,primary_slot: int=0) -> bool:
    if transport==null or identity!=manifest.scene_identity or mapping.size()<16 or instances.size()%96!=0:return false
    var count: int=instances.size()/96;var nodes: int=transport._count
    if mapping.decode_u32(0)!=count or mapping.decode_u32(4)!=nodes or nodes<1 or nodes>8192 or mapping.size()!=16+count*48+nodes*8 or primary_slot< -1 or primary_slot>=8:return false
    if _pending_field.get("transport")==transport and _pending_field.get("instances")==instances and _pending_field.get("original")==mapping:
        _mutex.lock();_pending_field.indirect=indirect;_pending_field.primary=primary_slot;_mutex.unlock();return true
    var owners: PackedByteArray=transport._field_packets.get(24,PackedByteArray());var optics: PackedByteArray=transport._field_packets.get(19,PackedByteArray());var covered: int=0
    if owners.size()!=nodes*4 or optics.size()!=16+nodes*64:return false
    for i in range(count):
        var at: int=i*96;var basis:=Basis(Vector3(instances.decode_float(at),instances.decode_float(at+4),instances.decode_float(at+8)),Vector3(instances.decode_float(at+16),instances.decode_float(at+20),instances.decode_float(at+24)),Vector3(instances.decode_float(at+32),instances.decode_float(at+36),instances.decode_float(at+40)))
        if not basis.is_finite() or absf(basis.determinant())<1e-12:return false
        var normal_basis: Basis=basis.inverse().transposed()
        for face in range(6):
            var offset: int=16+(i*6+face)*8;var first: int=mapping.decode_u32(offset);var size: int=mapping.decode_u32(offset+4);var expected: Vector3=(normal_basis[face/2]*(1. if face%2==0 else -1.)).normalized()
            if size<1 or first!=covered or first+size>nodes:return false
            for node in range(first,first+size):
                var o: int=16+count*48+node*8;var n: int=16+node*64+48;var normal:=Vector3(optics.decode_float(n),optics.decode_float(n+4),optics.decode_float(n+8))
                if owners.decode_u32(node*4)!=i or mapping.decode_u32(o)!=first or mapping.decode_u32(o+4)!=size or normal.dot(expected)<.999:return false
            covered+=size
    if covered!=nodes:return false
    _mutex.lock();_pending_field={"transport":transport,"instances":instances.duplicate(),"original":mapping.duplicate(),"indirect":indirect,"primary":primary_slot};_mutex.unlock();return true
func _frame_signature(next: Dictionary) -> PackedByteArray:
    _mutex.lock();_field_context=_pending_field.duplicate();_mutex.unlock();_field_receipt={}
    if not _field_context.is_empty() and _field_context.instances==next.instances:
        _field_receipt=_field_context.transport.render_binding(_rd)
    var signature: PackedByteArray=super._frame_signature(next);signature.append_array(var_to_bytes([_field_receipt.get("producer",0),_field_receipt.get("epoch",""),_field_receipt.get("solve",0),_field_context.get("indirect",false),_field_context.get("primary",-1)]));return signature
func _sync_field() -> void:
    var bytes:=PackedByteArray();bytes.resize(16)
    if not _field_receipt.is_empty():
        bytes=_field_context.original.duplicate();bytes.encode_u32(8,3 if _field_context.indirect else 1);bytes.encode_u32(12,0xffffffff if _field_context.primary<0 else _field_context.primary)
    var stamp: PackedByteArray=bytes.duplicate();stamp.append_array(var_to_bytes([_field_receipt.get("producer",0),_field_receipt.get("epoch","")]))
    if stamp==_field_map_stamp:return
    _clear_sets()
    if _field_map.is_valid():_rd.free_rid(_field_map);allocation_bytes-=_field_map_bytes
    _field_map=_rd.storage_buffer_create(bytes.size(),bytes);_field_map_bytes=bytes.size();allocation_bytes+=bytes.size();_field_map_stamp=stamp;_field_bound=_field_receipt.duplicate();_make_set()
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
        var patch:=PackedByteArray();patch.resize(48);_field_dummy_patch=_rd.storage_buffer_create(48,patch);var light:=PackedByteArray();light.resize(272);_field_dummy_light=_rd.storage_buffer_create(272,light);var map:=PackedByteArray();map.resize(16);_field_map=_rd.storage_buffer_create(16,map);_field_map_bytes=16
        var format:=RDTextureFormat.new();format.width=1;format.height=1;format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT;format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT;_field_dummy_image=_rd.texture_create(format,RDTextureView.new(),[]);allocation_bytes+=352
        _sources_ready=true
    if _kernels.is_empty():
        for stage in [1,2,3,4,7,8]:
            var spirv: RDShaderSPIRV=Kernels.SHADERS[stage].get_spirv()
            if spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)!="":failure="Scene kernel compile";return
            var shader: RID=_shader if stage==1 else _rd.shader_create_from_spirv(spirv);var pipeline: RID=_pipeline if stage==1 else _rd.compute_pipeline_create(shader)
            _kernels[stage]={"shader":shader,"pipeline":pipeline}
    for stage in _kernels:
        var order: Array=_resident_banks.keys() if stage in [2,3,8] else [0]
        for bank in order:
            # Resizing can rebuild sets before _sync_field. Always use this
            # frame's validated producer receipt, never a previous producer RID.
            var handles: Dictionary=_buffers.duplicate();handles.merge(_images);handles[6]=_params[bank];handles[14]=_dummy;handles[15]=_dummy_limits;handles[16]=_field_map;handles[17]=_field_receipt.get("patches",_field_dummy_patch);handles[18]=_field_receipt.get("irradiance",_field_dummy_image);handles[19]=_field_receipt.get("direct",_field_dummy_light)
            handles[20]=_bank_jobs[bank].rid if _bank_jobs.has(bank) else _dummy
            if _resident_banks.has(bank):
                var row: Dictionary=_resident_banks[bank];handles[0]=row.core.rid;handles[14]=row.optical.rid if row.has("optical") else _dummy;handles[15]=row.limits
            var uniforms: Array[RDUniform]=[]
            for binding in Kernels.BINDINGS[stage]:uniforms.append(_uniform(binding,handles[binding],binding in [11,12,18]))
            var set_rid: RID=_rd.uniform_set_create(uniforms,_kernels[stage].shader,0)
            if not set_rid.is_valid():failure="Scene descriptors";return
            _sets[str(bank)+":"+str(stage)]=set_rid
    _set=_sets["0:1"]
func _release_bank(row: Dictionary) -> void:
    SharedSamples.release_handle(_rd,row.core)
    if row.has("optical"):SharedSamples.release_handle(_rd,row.optical)
    _rd.free_rid(row.limits);allocation_bytes-=int(row.bytes)+int(row.limit_bytes);total_source_bytes-=int(row.bytes)
func _prepare_frame(next: Dictionary) -> Dictionary:
    var geometry_stamp: PackedByteArray=next.instances.duplicate();geometry_stamp.append_array(next.jobs)
    if geometry_stamp==_job_signature:
        _sync_field();var cached: Dictionary=next.duplicate();cached.jobs=_translated_jobs;return cached
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
    _clear_sets()
    for row in _bank_jobs.values():_rd.free_rid(row.rid)
    _bank_jobs.clear();allocation_bytes-=_bank_job_bytes;_bank_job_bytes=0
    var dispatches: Dictionary={}
    for i in range(0,jobs.size(),4):
        var bank: int=int(instances.decode_float(jobs[i+2]*96+68))
        if not dispatches.has(bank):dispatches[bank]={"data":PackedInt32Array(),"work":0}
        var row: Dictionary=dispatches[bank];row.data.append_array(PackedInt32Array([row.work,jobs[i+3],i/4,0]));row.work+=jobs[i+1]
    for bank in dispatches:
        var row: Dictionary=dispatches[bank];var data: PackedByteArray=row.data.to_byte_array()
        _bank_jobs[bank]={"rid":_rd.storage_buffer_create(data.size(),data),"work":row.work,"jobs":row.data.size()/4};_bank_job_bytes+=data.size()
    allocation_bytes+=_bank_job_bytes;_make_set()
    _sync_field()
    _job_signature=geometry_stamp;_translated_jobs=translated.to_byte_array()
    var result: Dictionary=next.duplicate();result.jobs=_translated_jobs;failure="";return result
func _release_uncommitted(row: Dictionary) -> void:
    if row.get("core",{}).get("ok",false):SharedSamples.release_handle(_rd,row.core)
    if row.get("optical",{}).get("ok",false):SharedSamples.release_handle(_rd,row.optical)
    if row.get("limits",RID()).is_valid():_rd.free_rid(row.limits)
func _update_parameters(parameters: PackedByteArray) -> void:
    _reverse_passes=parameters.decode_float(216)>.5
    for i in range(banks.size()):
        var row: Dictionary=_resident_banks.get(i,{});var data: PackedByteArray=parameters.duplicate();data.encode_float(208,float(row.get("limit_count",0)));data.encode_float(248,float(i));data.encode_float(252,parameters.decode_float(252) if row.has("optical") else 0.)
        if _bank_jobs.has(i):data.encode_s32(80,_bank_jobs[i].work);data.encode_s32(84,_bank_jobs[i].jobs)
        _rd.buffer_update(_params[i],0,256,data)
func _dispatch_stage(commands: int,count: int) -> void:
    var groups: int=ceili(float(count)/64);var x: int=mini(groups,32768);_rd.compute_list_dispatch(commands,x,ceili(float(groups)/x),1)
func _record_stage(commands: int,stage: int,count: int) -> void:
    var order: Array=_resident_banks.keys() if stage in [2,3,8] else [0];order.sort()
    if _reverse_passes and stage in [2,3,8]:order.reverse()
    for i in order:
        _rd.compute_list_bind_compute_pipeline(commands,_kernels[stage].pipeline);_rd.compute_list_bind_uniform_set(commands,_sets[str(i)+":"+str(stage)],0);_rd.compute_list_set_push_constant(commands,PackedInt32Array([stage,2,int(_reset_view),int(_reset_shadow)]).to_byte_array(),16);_dispatch_stage(commands,_bank_jobs[i].work if stage in [2,3,8] else count);_rd.compute_list_add_barrier(commands)
func _capture() -> void:
    super._capture()
    if not gpu_ready:return
    var shadow: PackedByteArray=_rd.buffer_get_data(_buffers[13])
    _mutex.lock();_readback["library_bytes"]=total_source_bytes;_readback["exclusive_allocation_bytes"]=allocation_bytes-total_source_bytes;_readback["banks"]=banks.size();_readback["shadow"]=shadow;_readback["resident_banks"]=_resident_banks.size();_readback["catalog_source_bytes"]=catalog_source_bytes;_readback["page_io_bytes"]=page_io_bytes;_readback["residency_changes"]=residency_changes;_readback["projection_capacity"]=projection_capacity;_readback["pass_counts"]=_pass_counts.duplicate();_mutex.unlock()
    _mutex.lock();_readback["field"]={"ready":not _field_receipt.is_empty(),"nodes":_field_receipt.get("nodes",0),"bytes":_field_receipt.get("bytes",0),"solve":_field_receipt.get("solve",0),"producer":_field_receipt.get("producer",0),"indirect":_field_context.get("indirect",false)};_readback["failure"]=failure;_mutex.unlock()
func _release() -> void:
    _clear_sets()
    for row in _bank_jobs.values():_rd.free_rid(row.rid)
    _bank_jobs.clear();allocation_bytes-=_bank_job_bytes;_bank_job_bytes=0
    _job_signature=PackedByteArray();_translated_jobs=PackedByteArray();_view_stamp=PackedByteArray();_shadow_stamp=PackedByteArray();_uploaded_geometry=PackedByteArray();_frame_passes.clear();_pass_counts.clear()
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
    for rid in [_field_map,_field_dummy_patch,_field_dummy_light,_field_dummy_image]:
        if rid.is_valid():_rd.free_rid(rid)
    _field_map=RID();_field_dummy_patch=RID();_field_dummy_light=RID();_field_dummy_image=RID();_field_map_bytes=0;_field_map_stamp=PackedByteArray();_field_bound={};_field_receipt={};_field_context={}
    if _buffers.has(0) and _buffers[0].is_valid():_rd.free_rid(_buffers[0]);_buffers.erase(0)
    super._release()
