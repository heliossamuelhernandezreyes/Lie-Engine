extends "res://lie28_building_effect.gd"
## Captured camera + shared resident transport. Original meshes stay offline.
const Kernels=preload("res://lie_brick_reference_kernels.gd")
var transport: CompositorEffect
var bench_packet:=PackedByteArray()
var _kernels: Dictionary={}
var _sets: Dictionary={}
func capture_root() -> String:return "res://captures/brick_reference/"
func shader_resource() -> RDShaderFile:return Kernels.SHADERS[1]
func _buffer(binding: int,length: int,data: PackedByteArray=PackedByteArray()) -> void:
    super._buffer(binding,length*8 if binding==13 else length,data)
func _make_set() -> void:
    if not _buffers.has(14):_buffer(14,bench_packet.size(),bench_packet)
    for rid in _sets.values():
        if _rd.uniform_set_is_valid(rid):_rd.free_rid(rid)
    _sets.clear();_set=RID()
    var handles: Dictionary=_buffers.duplicate();handles.merge(_images)
    handles[15]=transport.output_rid;handles[16]=transport.surface_light_codes_rid();handles[18]=transport.emission_descriptors_rid()
    if _kernels.is_empty():
        for stage in Kernels.SHADERS:
            if OS.get_environment("LIE_BRICK_TRACE")=="1":print("BRICK PIPELINE ",stage)
            var spirv: RDShaderSPIRV=Kernels.SHADERS[stage].get_spirv()
            if spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)!="":failure="Stage compile "+str(stage);return
            var shader: RID=_shader if stage==1 else _rd.shader_create_from_spirv(spirv)
            var pipeline: RID=_pipeline if stage==1 else _rd.compute_pipeline_create(shader)
            _kernels[stage]={"shader":shader,"pipeline":pipeline}
            if not shader.is_valid() or not pipeline.is_valid():failure="Stage pipeline "+str(stage);return
    for stage in _kernels:
        var uniforms: Array[RDUniform]=[]
        for binding in Kernels.BINDINGS[stage]:uniforms.append(_uniform(binding,handles[binding],binding in [8,9,11,12,15]))
        _sets[stage]=_rd.uniform_set_create(uniforms,_kernels[stage].shader,0)
        if not _sets[stage].is_valid():failure="Stage descriptors "+str(stage);return
    _set=_sets[1]
func _bind_stage(commands: int,stage: int) -> void:
    if OS.get_environment("LIE_BRICK_TRACE")=="1":print("BRICK CAMERA STAGE ",stage)
    _rd.compute_list_bind_compute_pipeline(commands,_kernels[stage].pipeline)
    _rd.compute_list_bind_uniform_set(commands,_sets[stage],0)
func _run_stage(stage: int) -> bool:
    var limit: String=OS.get_environment("LIE_BRICK_MAX_STAGE")
    return limit.is_empty() or stage<=int(limit)
func _release() -> void:
    for stage in _sets:
        if stage!=1 and _rd.uniform_set_is_valid(_sets[stage]):_rd.free_rid(_sets[stage])
    _sets.clear()
    for stage in _kernels:
        if stage!=1:
            for rid in [_kernels[stage].pipeline,_kernels[stage].shader]:
                if rid.is_valid():_rd.free_rid(rid)
    _kernels.clear();super._release()
func _render_callback(kind: int,data: RenderData) -> void:
    if transport==null or not transport.gpu_ready:return
    _mutex.lock()
    if _pending.has("parameters"):_pending.parameters.encode_float(248,float(transport.frame_count))
    _mutex.unlock()
    super._render_callback(kind,data)
