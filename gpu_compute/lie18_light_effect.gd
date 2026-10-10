extends "res://lie15_light_effect.gd"
## Geometry, materials and instances publish together on the render thread.
## Three GPU stages rebuild reciprocal bounded form factors only when needed.
const Shader18: RDShaderFile=preload("res://shaders/lie18_transport.glsl")
var render_poses: Array[Transform3D]=[]
var render_slots: Array=[]
var render_signature: String=""
var graph_rebuilds: int=0
var _factor_caps: RID

func configure_workshop(model: Dictionary) -> bool:
    if not Model.valid(model): return false
    var count: int=model["patches"].size()
    if _count!=0 and count!=_count: return false
    _count=count; _triangle_count=0
    var config: PackedByteArray=PackedInt32Array([count,model["lights"].size(),int(model["bounces"]),0]).to_byte_array()
    var policy: Dictionary=model["secondary_radii"]
    config.append_array(PackedFloat32Array([.0025,0,0,1,float(policy["radius_max"]),float(policy["radius_decay"]),float(policy["power_reference"]),float(model["optical_sheets"].size())]).to_byte_array())
    var zeros:=PackedByteArray(); zeros.resize(count*count*4)
    var next: Dictionary={0:Model.patch_bytes(model),1:Model.light_bytes(model),2:zeros,8:config,9:Model.blocker_bytes(model),11:Model.triangle_bytes(model),12:Model.radius_bytes(model),13:Optics.bytes(model["optical_sheets"]),
        "lights":model["lights"].size(),"bounces":int(model["bounces"]),"instance":model["instance_bytes"],"poses":model["poses"].duplicate(),"slots":model["slots"].duplicate(),"signature":model["signature"]}
    _lock.lock(); _pending=next; _instance_bytes=model["instance_bytes"]; _lock.unlock()
    return true

func _transport_file() -> RDShaderFile:
    return Shader18

func _extra_transport_uniforms() -> Array[RDUniform]:
    var uniforms: Array[RDUniform]=super._extra_transport_uniforms()
    _factor_caps=_rd.storage_buffer_create(_count*4)
    allocation_bytes+=_count*4
    uniforms.append(_uniform(16,_factor_caps))
    return uniforms

func _render_callback(kind: int,_render_data: RenderData) -> void:
    if kind!=EFFECT_CALLBACK_TYPE_PRE_OPAQUE or _count==0: return
    _lock.lock(); var data: Dictionary=_pending; _pending={}; _lock.unlock()
    if data.is_empty(): return
    if not gpu_ready and not _initialize_gpu(data): return
    for key in data:
        if key is int:
            var bytes: PackedByteArray=data[key]
            _rd.buffer_update(_buffers[key-1 if key>=11 else key],0,bytes.size(),bytes)
    var instances: PackedByteArray=data["instance"]
    _rd.buffer_update(instance_rid,0,instances.size(),instances)
    _light_count=int(data["lights"]); _bounces=int(data["bounces"])
    var commands: int=_rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(commands,_pipeline)
    _rd.compute_list_bind_uniform_set(commands,_set,0)
    _dispatch(commands,6,_count*_count); _dispatch(commands,7,_count); _dispatch(commands,8,_count*_count)
    _dispatch(commands,0,_count*_light_count); _dispatch(commands,1,_light_count); _dispatch(commands,2,_count)
    for generation in range(_bounces): _dispatch(commands,3,_count,generation%2)
    _dispatch(commands,4,_count); _rd.compute_list_end()
    render_poses.assign(data["poses"]); render_slots=data["slots"].duplicate(); render_signature=data["signature"]
    graph_rebuilds+=1; frame_count+=1

func _capture_data() -> void:
    super._capture_data()
    if not gpu_ready: return
    var factors: PackedFloat32Array=_rd.buffer_get_data(_buffers[2]).to_float32_array()
    _lock.lock(); _readback["form_factors"]=factors; _readback["graph_rebuilds"]=graph_rebuilds; _lock.unlock()

func _release_gpu() -> void:
    super._release_gpu()
    if _factor_caps.is_valid(): _rd.free_rid(_factor_caps)
