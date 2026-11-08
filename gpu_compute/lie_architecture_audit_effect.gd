extends "res://lie_construction_scene_effect.gd"
## Diagnostic-only: exports exact GPU inputs/SPIR-V and output hashes for
## native replay. Explicit readbacks occur OUTSIDE the timed render interval.
var _audit_result: Dictionary={}
var _audit_cpu_frames: Array=[]
var _audit_stage_cpu: Array=[]
func _render_callback(kind: int,data: RenderData) -> void:
    var before: int=frame_count;var started: int=Time.get_ticks_usec();_audit_stage_cpu=[]
    super._render_callback(kind,data)
    if frame_count!=before:
        _audit_cpu_frames.append({"serial":frame_count,"callback_elapsed_ms":float(Time.get_ticks_usec()-started)/1000.,"stages":_audit_stage_cpu.duplicate(true)})
        if _audit_cpu_frames.size()>32:_audit_cpu_frames.pop_front()
func _record_stage(commands: int,stage: int,count: int) -> void:
    var started: int=Time.get_ticks_usec();super._record_stage(commands,stage,count)
    _audit_stage_cpu.append({"stage":stage,"name":PASS_NAMES[stage],"record_elapsed_ms":float(Time.get_ticks_usec()-started)/1000.})
func export_fixture(path: String,start_serial: int) -> void:
    _mutex.lock();_audit_result={};_mutex.unlock()
    RenderingServer.call_on_render_thread(Callable(self,"_export_fixture").bind(path,start_serial))
func export_result() -> Dictionary:
    _mutex.lock();var result: Dictionary=_audit_result.duplicate(true);_mutex.unlock();return result
func _audit_write(path: String,data: PackedByteArray) -> Dictionary:
    var file:=FileAccess.open(path,FileAccess.WRITE)
    if file==null:return {"error":"write","path":path}
    file.store_buffer(data);file.close()
    return {"bytes":data.size(),"sha256":_audit_hash(data)}
func _audit_hash(data: PackedByteArray) -> String:
    var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(data);return hash.finish().hex_encode()
func _export_fixture(path: String,start_serial: int) -> void:
    if not gpu_ready:return
    DirAccess.make_dir_recursive_absolute(path)
    var result: Dictionary={"schema":"lie-architecture-replay-fixture/1","device":_rd.get_device_name(),"output_size":output_size,"internal_size":render_size,"projection_capacity":projection_capacity,"projection_stride":_projection_stride(),"samples":sample_invocations,"camera_samples":_camera_work,"instances":instance_count,"serial":frame_count,"banks":[],"inputs":{},"reference":{},"physical_android_tested":false,"scope":"Exact captured GPU inputs and original Godot-compiled SPIR-V; output hashes cover depth, owner and material accumulators. Diagnostic readbacks are outside benchmark timestamps."}
    result.inputs["projection-stride.txt"]=_audit_write(path+"/projection-stride.txt",str(_projection_stride()).to_utf8_buffer())
    for binding in [1,2,6]:result.inputs["common-"+str(binding)+".bin"]=_audit_write(path+"/common-"+str(binding)+".bin",_rd.buffer_get_data(_buffers[binding]))
    var order: Array=_camera_jobs.keys();order.sort()
    for bank in order:
        var row: Dictionary=_resident_banks[bank];var handles: Dictionary={0:row.core.rid,6:_camera_params[bank],14:row.optical.rid if row.has("optical") else _dummy,15:row.limits,20:_camera_jobs[bank].rid}
        result.banks.append({"id":bank,"work":_camera_jobs[bank].work})
        for binding in handles:
            var name: String="bank-%d-%d.bin" % [bank,binding];result.inputs[name]=_audit_write(path+"/"+name,_rd.buffer_get_data(handles[binding]))
    for stage in [1,2,3]:
        var name: String="stage-"+str(stage)+".spv";result.inputs[name]=_audit_write(path+"/"+name,Kernels.SHADERS[stage].get_spirv().get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE))
    for variant in ["hoist","cache"]:
        if not ResourceLoader.exists("res://shaders/audit-"+variant+"-2.glsl"):continue
        DirAccess.make_dir_recursive_absolute(path+"/"+variant)
        for stage in [1,2,3]:
            var shader: RDShaderFile=Kernels.SHADERS[1] if stage==1 else load("res://shaders/audit-"+variant+"-"+str(stage)+".glsl")
            var name: String=variant+"/stage-"+str(stage)+".spv";result.inputs[name]=_audit_write(path+"/"+name,shader.get_spirv().get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE))
    for binding in [4,5,7]:
        var bytes: PackedByteArray=_rd.buffer_get_data(_buffers[binding]);result.reference[str(binding)]={"bytes":bytes.size(),"sha256":_audit_hash(bytes)}
    _collect_profile()
    for row in _profiles:
        if row.serial==frame_count:result.godot_profile=row.duplicate(true)
    for row in _audit_cpu_frames:
        if row.serial==frame_count:result.godot_cpu=row.duplicate(true)
    result.godot_profiles=[];result.godot_cpu_samples=[]
    for row in _profiles:
        if row.serial>=start_serial:result.godot_profiles.append(row.duplicate(true))
    for row in _audit_cpu_frames:
        if row.serial>=start_serial:result.godot_cpu_samples.append(row.duplicate(true))
    var layout: String="%d %d %d\n" % [render_size,projection_capacity,order.size()]
    for bank in order:layout+="%d %d\n" % [bank,_camera_jobs[bank].work]
    _audit_write(path+"/layout.txt",layout.to_utf8_buffer())
    _audit_write(path+"/fixture.json",JSON.stringify(result,"  ").to_utf8_buffer())
    _mutex.lock();_audit_result=result;_mutex.unlock()
