extends RefCounted
## An emissive neutral surface has radiance .25 and display color .2.
## Execute the production visibility/coverage/color passes with one very weak
## contribution, then a known weighted pair. The oracle is independent of the
## integer accumulator, and catches black/white rounding at small coverage.
const ShaderFile: RDShaderFile=preload("res://shaders/lie16_pipeline.glsl")
const Helper=preload("res://lie16_temporal_fixture.gd")
const SIDE: int=8

static func run() -> Dictionary:
    var rd: RenderingDevice=RenderingServer.create_local_rendering_device()
    if rd==null: return {"error":"Actual Vulkan device unavailable"}
    var shader: RID=rd.shader_create_from_spirv(ShaderFile.get_spirv())
    var pipeline: RID=rd.compute_pipeline_create(shader)
    var report: Dictionary={}
    for name in ["one_coverage_unit","eight_coverage_units","weighted_crossfade"]:
        var weak: float=1.0/8192 if name=="one_coverage_unit" else 8.0/8192
        var pair: bool=name=="weighted_crossfade"
        var count: int=2 if pair else 1
        var samples:=PackedFloat32Array([0,0,0,.5,0,0,1,5,0,0,0,1,0,0,1,5])
        var tasks:=PackedFloat32Array()
        var projected:=PackedFloat32Array()
        for i in range(count):
            var weight: float=(.25 if i==0 else .75) if pair else weak
            tasks.append_array(PackedFloat32Array([i,1,0,weight,i,i+1,0,0,1,0,0,0,0,1,0,0,0,0,-1,0]))
            projected.append_array(PackedFloat32Array([4.5,4.5,3.6,weight,.75,.75,0,0]))
        var camera:=PackedFloat32Array([0,0,3.6,0,1,0,0,0,0,1,0,0,0,0,-1,0,1,1,.1,100]).to_byte_array()
        camera.append_array(PackedInt32Array([SIDE,SIDE,0,1]).to_byte_array())
        camera.append_array(PackedFloat32Array([0,0,2,0]).to_byte_array())
        var depths:=PackedInt32Array(); depths.resize(SIDE*SIDE)
        var sums:=PackedInt32Array(); sums.resize(SIDE*SIDE*4)
        var patches:=PackedFloat32Array(); patches.resize(6*12)
        var instance:=PackedFloat32Array([1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,0,.5,.5,.5,0,1,1,1,0,.3,0,.5,1])
        var counters:=PackedInt32Array(); counters.resize(16)
        var probe:=PackedInt32Array([0,0,0,0])
        var output_probe:=PackedFloat32Array(); output_probe.resize(8)
        var lights:=PackedFloat32Array(); lights.resize(8)
        var buffers: Array[PackedByteArray]=[samples.to_byte_array(),tasks.to_byte_array(),camera,projected.to_byte_array(),
            depths.to_byte_array(),sums.to_byte_array(),depths.to_byte_array(),patches.to_byte_array(),instance.to_byte_array(),
            probe.to_byte_array(),output_probe.to_byte_array(),lights.to_byte_array(),PackedFloat32Array([1]).to_byte_array(),
            counters.to_byte_array(),PackedFloat32Array([.01,.01]).to_byte_array(),depths.to_byte_array()]
        var bindings: Array=[0,1,2,3,4,5,6,12,14,16,17,18,19,20,21,22]
        var uniforms: Array[RDUniform]=[]
        var resources: Array[RID]=[]
        for i in range(buffers.size()):
            var rid: RID=rd.storage_buffer_create(buffers[i].size(),buffers[i])
            resources.append(rid); uniforms.append(Helper._uniform(int(bindings[i]),rid))
        var output: RID
        for binding in [7,11,15]:
            var format:=RDTextureFormat.new()
            format.width=SIDE; format.height=SIDE
            format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
            format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
            var zero:=PackedByteArray(); zero.resize(SIDE*SIDE*16)
            var rid: RID=rd.texture_create(format,RDTextureView.new(),[zero])
            resources.append(rid); uniforms.append(Helper._uniform(binding,rid,true))
            if binding==7: output=rid
        var set: RID=rd.uniform_set_create(uniforms,shader,0)
        var commands: int=rd.compute_list_begin()
        rd.compute_list_bind_compute_pipeline(commands,pipeline)
        rd.compute_list_bind_uniform_set(commands,set,0)
        for stage in [0,2,8,9,3,4]:
            var push: PackedByteArray=PackedInt32Array([stage,count,1,0]).to_byte_array()
            rd.compute_list_set_push_constant(commands,push,16)
            rd.compute_list_dispatch(commands,1,1,1)
            rd.compute_list_add_barrier(commands)
        rd.compute_list_end(); rd.submit(); rd.sync()
        var result: PackedFloat32Array=rd.texture_get_data(output,0).to_float32_array()
        var expected: float=.25*.2+.75/3.0 if pair else .2
        var center: int=(4*SIDE+4)*4
        var error: float=absf(result[center+3]-1)
        for c in range(3): error=maxf(error,absf(result[center+c]-expected))
        report[name]={"expected_display_rgb":expected,"actual_display_rgb":result[center],"maximum_error":error}
        rd.free_rid(set)
        for rid in resources: rd.free_rid(rid)
    rd.free_rid(pipeline); rd.free_rid(shader); rd.free()
    return report
