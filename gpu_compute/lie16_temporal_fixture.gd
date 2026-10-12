extends RefCounted
## Small independent numeric cases execute the SAME production resolve shader.
const ShaderFile: RDShaderFile=preload("res://shaders/lie16_temporal.glsl")
const SIDE: int=8

static func _uniform(binding: int,rid: RID,image: bool=false) -> RDUniform:
    var u:=RDUniform.new()
    u.binding=binding
    u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if image else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    u.add_id(rid)
    return u

static func _camera(eye: Vector3=Vector3.ZERO) -> PackedByteArray:
    var values:=PackedFloat32Array([eye.x,eye.y,eye.z,0,1,0,0,0,0,1,0,0,0,0,-1,0,1,1,.1,100])
    var result: PackedByteArray=values.to_byte_array()
    result.append_array(PackedInt32Array([SIDE,SIDE,0,0]).to_byte_array())
    result.append_array(PackedFloat32Array([0,0,0,0]).to_byte_array())
    return result

static func run() -> Dictionary:
    var rd: RenderingDevice=RenderingServer.create_local_rendering_device()
    if rd==null: return {"error":"No actual local Vulkan device"}
    var shader: RID=rd.shader_create_from_spirv(ShaderFile.get_spirv())
    var pipeline: RID=rd.compute_pipeline_create(shader)
    var report: Dictionary={}
    for name in ["accepted","other_owner","other_depth","background","camera_out","reset","reactive_light","articulated_owner"]:
        var resources: Array[RID]=[]
        var uniforms: Array[RDUniform]=[]
        var current:=PackedFloat32Array()
        var previous:=PackedFloat32Array()
        var depth:=PackedInt32Array()
        var owners:=PackedInt32Array()
        var previous_meta:=PackedInt32Array()
        for y in range(SIDE):
            for x in range(SIDE):
                var value: float=.3 if x==4 and y==3 else .2
                var alpha: float=0 if name=="background" and x==4 and y==4 else 1
                current.append_array(PackedFloat32Array([value,value,value,alpha]))
                var old: float=.9 if name=="reactive_light" else .25
                previous.append_array(PackedFloat32Array([old,old,old,1]))
                depth.append(PackedFloat32Array([2]).to_byte_array().decode_u32(0))
                owners.append(0)
                var old_depth: float=4 if name=="other_depth" else 2
                var old_owner: int=1 if name=="other_owner" or (name=="articulated_owner" and x!=3) else 0
                previous_meta.append_array(PackedInt32Array([PackedFloat32Array([old_depth]).to_byte_array().decode_u32(0),old_owner]))
        var format:=RDTextureFormat.new()
        format.width=SIDE; format.height=SIDE
        format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
        format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
        var output: RID
        for binding in range(3):
            var bytes: PackedByteArray=current.to_byte_array() if binding==0 else previous.to_byte_array()
            if binding==2: bytes=PackedByteArray(); bytes.resize(SIDE*SIDE*16)
            var image: RID=rd.texture_create(format,RDTextureView.new(),[bytes])
            resources.append(image); uniforms.append(_uniform(binding,image,true))
            if binding==2: output=image
        var poses:=PackedFloat32Array()
        var instances:=PackedFloat32Array()
        for i in range(15):
            var origin: float=.5 if name=="articulated_owner" and i==0 else 0
            instances.append_array(PackedFloat32Array([1,0,0,0,0,1,0,0,0,0,1,0,origin,0,0,0,.5,.5,.5,0,1,1,1,0,.3,0,0,1]))
            poses.append_array(PackedFloat32Array([1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,0]))
        var next_meta:=PackedByteArray(); next_meta.resize(SIDE*SIDE*8)
        var counters:=PackedInt32Array(); counters.resize(16)
        var arrays: Array[PackedByteArray]=[depth.to_byte_array(),owners.to_byte_array(),previous_meta.to_byte_array(),next_meta,
            _camera(),_camera(Vector3(10,0,0) if name=="camera_out" else Vector3.ZERO),instances.to_byte_array(),poses.to_byte_array(),counters.to_byte_array()]
        var counter_rid: RID
        for i in range(arrays.size()):
            var rid: RID=rd.storage_buffer_create(arrays[i].size(),arrays[i])
            resources.append(rid); uniforms.append(_uniform(i+3,rid))
            if i==8: counter_rid=rid
        var set: RID=rd.uniform_set_create(uniforms,shader,0)
        var commands: int=rd.compute_list_begin()
        rd.compute_list_bind_compute_pipeline(commands,pipeline)
        rd.compute_list_bind_uniform_set(commands,set,0)
        var push: PackedByteArray=PackedInt32Array([0 if name=="reset" else 1,1,0,0]).to_byte_array()
        push.append_array(PackedFloat32Array([.7,0,0,0]).to_byte_array())
        rd.compute_list_set_push_constant(commands,push,32)
        rd.compute_list_dispatch(commands,1,1,1)
        rd.compute_list_end(); rd.submit(); rd.sync()
        var actual: PackedFloat32Array=rd.texture_get_data(output,0).to_float32_array()
        var expected: float=.2
        if name in ["accepted","articulated_owner"]: expected+=.05*.7*exp(-.06 if name=="articulated_owner" else 0)*(1-.05/.12)
        var center: int=(4*SIDE+4)*4
        var error: float=0
        for c in range(3): error=maxf(error,absf(actual[center+c]-expected))
        error=maxf(error,absf(actual[center+3]-(0 if name=="background" else 1)))
        var counted: PackedInt32Array=rd.buffer_get_data(counter_rid).to_int32_array()
        report[name]={"maximum_center_error":error,"accepted_history_pixels":counted[8],"rejected_history_pixels":counted[9],"wrong_depth":counted[10],"wrong_owner":counted[11]}
        rd.free_rid(set)
        for rid in resources: rd.free_rid(rid)
    rd.free_rid(pipeline); rd.free_rid(shader); rd.free()
    return report
