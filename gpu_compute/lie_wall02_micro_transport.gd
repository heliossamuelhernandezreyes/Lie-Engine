extends "res://lie11_light_effect.gd"
## Source of ALL light energy remains LIE11. This specialization changes
## visibility in the LIE11 stage-0 direct flux kernel, not radiometry, power,
## absorption, reflectance, transmission or diffuse bounces.
const SHADER_WALL02: RDShaderFile=preload("res://shaders/lie_wall02_transport.glsl")
const NODES_PER_BRICK: int=9
const BRICKS: int=96
const MAX_BOXES: int=128
var _shadow_bounds: Array=[]
var _direct_shadows_enabled: bool=true
var _shadow_rid: RID
var _shadow_bytes: int=0
var _shadow_updates: int=0

func _transport_file() -> RDShaderFile:
    return SHADER_WALL02

func assign_shadow_boxes(value: Array) -> bool:
    if value.size()!=BRICKS or gpu_ready:
        return false
    var points: Array=[]
    for box in value:
        if not box is Array or box.size()!=2:
            return false
        var low: Array=box[0]
        var high: Array=box[1]
        if low.size()!=3 or high.size()!=3:
            return false
        for i in range(3):
            if not is_finite(float(low[i])) or not is_finite(float(high[i])) or float(low[i])>=float(high[i]):
                return false
        points.append(box)
    _shadow_bounds=points
    return true

func _shadow_buffer() -> PackedByteArray:
    var count: int=_shadow_bounds.size() if _direct_shadows_enabled else 0
    var header:=PackedInt32Array([count,NODES_PER_BRICK,BRICKS*NODES_PER_BRICK,0]).to_byte_array()
    var boxes:=PackedFloat32Array()
    for region in _shadow_bounds:
        var low: Array=region[0]
        var high: Array=region[1]
        boxes.append_array(PackedFloat32Array([float(low[0]),float(low[1]),float(low[2]),0]))
        boxes.append_array(PackedFloat32Array([float(high[0]),float(high[1]),float(high[2]),0]))
    header.append_array(boxes.to_byte_array())
    return header

func _extra_transport_uniforms() -> Array[RDUniform]:
    var uniforms: Array[RDUniform]=super._extra_transport_uniforms()
    var packed:=_shadow_buffer()
    if packed.size()==16:
        failure="LIE-WALL02 requires 96 spatial shadow occluders"
        return uniforms
    _shadow_rid=_rd.storage_buffer_create(packed.size(),packed)
    if not _shadow_rid.is_valid():
        failure="Failed to upload brick shadow visibility proxies"
        return uniforms
    _shadow_bytes=packed.size()
    allocation_bytes+=packed.size()
    uniforms.append(_uniform(17,_shadow_rid))
    return uniforms

func set_direct_shadow_enabled(enabled: bool) -> void:
    if _direct_shadows_enabled==enabled:
        return
    _direct_shadows_enabled=enabled
    if gpu_ready:
        RenderingServer.call_on_render_thread(Callable(self,"_update_shadow_header").bind(enabled))

func _update_shadow_header(enabled: bool) -> void:
    if not gpu_ready or not _shadow_rid.is_valid():
        return
    var count: int=_shadow_bounds.size() if enabled else 0
    _rd.buffer_update(_shadow_rid,0,16,
        PackedInt32Array([count,NODES_PER_BRICK,BRICKS*NODES_PER_BRICK,0]).to_byte_array())
    _shadow_updates+=1

func shadow_metrics() -> Dictionary:
    return {"direct_shadow_boxes":_shadow_bounds.size(),
            "direct_shadows_enabled":_direct_shadows_enabled,
            "shadow_storage_bytes":_shadow_bytes,
            "visibility_header_updates":_shadow_updates,
            "visible_source_triangles":0,
            "collision_proxies_allocated":0,
            "base_energy_transport":"original LIE11"}

func _release_gpu() -> void:
    if _rd!=null and _shadow_rid.is_valid():
        _rd.free_rid(_shadow_rid)
        _shadow_rid=RID()
    super._release_gpu()
