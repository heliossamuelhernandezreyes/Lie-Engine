extends "res://lie28_building_effect.gd"
## Shared immutable scan bank; separate compiled entries for driver isolation.
const Kernels=preload("res://lie_scanned_masonry_kernels.gd")
var _kernels: Dictionary={}
var _sets: Dictionary={}
func capture_root() -> String:return "res://captures/scanned_masonry/"
func shader_resource() -> RDShaderFile:return Kernels.SHADERS[1]
func instance_capacity() -> int:return 8192
func work_capacity() -> int:return 3000000
func _init(size: int=720) -> void:
    super._init(512);output_size=clampi(size,256,720);render_size=output_size*2
func _make_set() -> void:
    for rid in _sets.values():
        if _rd.uniform_set_is_valid(rid):_rd.free_rid(rid)
    _sets.clear();_set=RID()
    var handles: Dictionary=_buffers.duplicate();handles.merge(_images)
    if _kernels.is_empty():
        for stage in Kernels.SHADERS:
            var spirv: RDShaderSPIRV=Kernels.SHADERS[stage].get_spirv()
            if spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)!="":failure="Stage compile "+str(stage);return
            var shader: RID=_shader if stage==1 else _rd.shader_create_from_spirv(spirv)
            var pipeline: RID=_pipeline if stage==1 else _rd.compute_pipeline_create(shader)
            _kernels[stage]={"shader":shader,"pipeline":pipeline}
            if not shader.is_valid() or not pipeline.is_valid():failure="Stage pipeline "+str(stage);return
    for stage in _kernels:
        var uniforms: Array[RDUniform]=[]
        for binding in Kernels.BINDINGS[stage]:uniforms.append(_uniform(binding,handles[binding],binding in [8,9,11,12]))
        _sets[stage]=_rd.uniform_set_create(uniforms,_kernels[stage].shader,0)
        if not _sets[stage].is_valid():failure="Stage descriptors "+str(stage);return
    _set=_sets[1]
func _bind_stage(commands: int,stage: int) -> void:
    _rd.compute_list_bind_compute_pipeline(commands,_kernels[stage].pipeline)
    _rd.compute_list_bind_uniform_set(commands,_sets[stage],0)
func _release() -> void:
    for stage in _sets:
        if stage!=1 and _rd.uniform_set_is_valid(_sets[stage]):_rd.free_rid(_sets[stage])
    _sets.clear()
    for stage in _kernels:
        if stage!=1:
            for rid in [_kernels[stage].pipeline,_kernels[stage].shader]:
                if rid.is_valid():_rd.free_rid(rid)
    _kernels.clear();super._release()
