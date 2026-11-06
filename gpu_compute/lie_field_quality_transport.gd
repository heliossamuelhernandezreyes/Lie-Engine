extends "res://lie_area_light_transport.gd"
## Same scene/source/lighting bridge, with area budgets and adaptive sectors.
const Quality=preload("res://lie_field_quality_model.gd")
const QualityShader=preload("res://shaders/lie_field_quality_area.glsl")
var _quality_options: Dictionary=Quality.DEFAULTS.duplicate(true)
var _quality_areas: Array=[]
var _quality_bytes:=PackedByteArray()
var _quality_desired:=PackedByteArray()
var _quality_rids: Dictionary={}
var quality_updates: int=0
func _transport_file() -> RDShaderFile:return QualityShader
func _quality_dispatch(commands: int,stage: int,threads: int,ping: int) -> void:
    _rd.compute_list_set_push_constant(commands,PackedInt32Array([stage,ping,0,0]).to_byte_array(),16)
    _rd.compute_list_dispatch(commands,ceili(float(threads)/64.),1,1);_rd.compute_list_add_barrier(commands)
func _dispatch(commands: int,stage: int,threads: int,ping: int=0) -> void:
    if stage==3 and _gpu_optics and _gpu_separate:
        var count: int=_count*_light_count
        _quality_dispatch(commands,5,count,ping)
        _quality_dispatch(commands,3,count*6,ping)
        _quality_dispatch(commands,7,count,ping)
        return
    super._dispatch(commands,stage,threads,ping)
func configure(model: Dictionary) -> bool:
    var areas: Array=[]
    for patch in model.get("patches",[]):areas.append(patch.get("area",0))
    var options: Variant=model.get("field_quality",_quality_options)
    if not options is Dictionary:return false
    var bytes: PackedByteArray=Quality.packet(areas,options)
    if bytes.is_empty():return false
    var normalized: Dictionary=Quality.DEFAULTS.duplicate(true);normalized.merge(options,true)
    if not _quality_areas.is_empty():
        if normalized.visibility_revision<_quality_options.visibility_revision:return false
        if normalized.dynamic_occluders!=_quality_options.dynamic_occluders and normalized.visibility_revision<=_quality_options.visibility_revision:return false
    if not model.get("optical_sheets",[]).is_empty():return false
    # Validate all base contracts before committing the new desired policy.
    if not Model.valid(model) or not _valid_point_codes(model.get("lights",[])) or _validated_emission(model).is_empty() or factor_input_bytes(model).is_empty():return false
    if (_count!=0 and areas.size()!=_count) or (_triangle_count!=-1 and model.get("triangles",[]).size()!=_triangle_count):return false
    _quality_areas=areas;_quality_options=normalized
    _quality_desired=bytes
    return super.configure(model)
func _additional_transport_data(model: Dictionary) -> Dictionary:
    var result: Dictionary=super._additional_transport_data(model)
    result["quality_bytes"]=_quality_desired
    result["force"]=bool(result.get("force",false)) or _quality_desired!=_quality_bytes
    return result
func _before_transport_update(data: Dictionary) -> void:
    super._before_transport_update(data)
    if data.has("quality_bytes"):
        _quality_bytes=data["quality_bytes"]
        if _quality_rids.has(27):_rd.buffer_update(_quality_rids[27],0,_quality_bytes.size(),_quality_bytes)
        quality_updates+=1
func _extra_transport_uniforms() -> Array[RDUniform]:
    var result: Array[RDUniform]=super._extra_transport_uniforms()
    for binding in [27,28,29,30]:
        var bytes: PackedByteArray=_quality_bytes if binding==27 else PackedByteArray()
        if binding!=27:bytes.resize(_count*MAX_FIELD_LIGHTS*6*(16 if binding==30 else 32))
        var rid: RID=_rd.storage_buffer_create(bytes.size(),bytes)
        if not rid.is_valid():failure="Field quality allocation";return []
        _quality_rids[binding]=rid;allocation_bytes+=bytes.size();result.append(_uniform(binding,rid))
    return result
func set_field_quality(options: Dictionary) -> bool:
    var bytes: PackedByteArray=Quality.packet(_quality_areas,options)
    if bytes.is_empty():return false
    var next: Dictionary=Quality.DEFAULTS.duplicate(true);next.merge(options,true)
    if next.dynamic_occluders!=_quality_options.dynamic_occluders and next.visibility_revision<=_quality_options.visibility_revision:return false
    if next.visibility_revision<_quality_options.visibility_revision:return false
    if bytes==_quality_desired:return true
    _quality_options=next;_quality_desired=bytes
    _lock.lock();_pending["quality_bytes"]=bytes;_pending["force"]=true;_lock.unlock()
    return true
func set_dynamic_occluders(boxes: Array,expected_revision: int,new_revision: int) -> bool:
    if expected_revision!=_quality_options.visibility_revision or new_revision<=expected_revision:return false
    var next: Dictionary=_quality_options.duplicate(true)
    next.dynamic_occluders=boxes.duplicate(true);next.visibility_revision=new_revision
    return set_field_quality(next)
func direct_response_inputs() -> Dictionary:
    var result: Dictionary=super.direct_response_inputs()
    result.signature["field_quality"]=_quality_bytes
    return result
func quality_codes_rid() -> RID:return _quality_rids.get(27,RID()) if gpu_ready else RID()
func optical_metrics() -> Dictionary:
    var result: Dictionary=super.optical_metrics()
    result["quality"]={"policy":_quality_options.duplicate(true),"updates":quality_updates,"max_sectors":6,"scope":"opaque; area-weighted local tolerance, not a global image-error guarantee; dynamic AABB visibility; moments within sectors remain approximate"}
    return result
func _release_gpu() -> void:
    # The parent releases the uniform set before any bound buffer is freed.
    # Freeing a quality buffer first auto-invalidates that set on Vulkan.
    super._release_gpu()
    for rid in _quality_rids.values():
        if rid.is_valid():_rd.free_rid(rid)
    _quality_rids.clear()
