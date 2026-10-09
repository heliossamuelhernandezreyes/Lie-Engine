extends SceneTree
## Explicit, mandatory Vulkan compute check of actual 3D reprojection.
func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var rd: RenderingDevice = RenderingServer.create_local_rendering_device()
    if rd==null:
        _fail("No Vulkan compute RenderingDevice")
        return
    var shader_file: RDShaderFile=load("res://shaders/project_samples.glsl") as RDShaderFile
    if shader_file==null:
        _fail("Projection compute shader not imported")
        return
    var code: RDShaderSPIRV=shader_file.get_spirv()
    var error: String=code.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
    if error!="":
        _fail("SPIR-V compilation failed: "+error)
        return
    var shader: RID=rd.shader_create_from_spirv(code)
    if not shader.is_valid():
        _fail("Projection shader RID invalid")
        return
    var samples:=PackedFloat32Array([
        0.5,0.5,0.5,1.0,  # center => screen [64,64], depth 6
        0.6,0.5,0.5,1.0,  # camera-right offset -> ~68.24 px
        5.0,0.5,0.5,1.0,  # completely outside target view
        0.5,0.5,0.5,0.0,  # invisible alpha -> invalid
        0.5,0.5,0.1,1.0   # near source depth -> nearer target-camera point
    ])
    var meta:=PackedFloat32Array([
        # source capture origin (0,0,3.825)
        0,0,3.825,0,
        # source camera right, up, forward into model
        1,0,0,0, 0,1,0,0, 0,0,-1,0,
        # target camera at (0,0,6), axis right +X, up +Y, forward -Z
        0,0,6,0, 1,0,0,0, 0,1,0,0, 0,0,-1,0,
        # source capture ortho scale, near, far, target width
        2.295,2.72,4.93,128,
        # tan(60deg/2), aspect=1, near=0.1, far=100
        0.57735026919,1,0.1,100
    ])
    var out:=PackedFloat32Array()
    out.resize(samples.size())
    var buffers: Array[RID]=[
        rd.storage_buffer_create(samples.to_byte_array().size(),samples.to_byte_array()),
        rd.storage_buffer_create(meta.to_byte_array().size(),meta.to_byte_array()),
        rd.storage_buffer_create(out.to_byte_array().size(),out.to_byte_array())
    ]
    var uniforms: Array[RDUniform]=[]
    for i in range(3):
        var u:=RDUniform.new()
        u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u.binding=i
        u.add_id(buffers[i])
        uniforms.append(u)
    var uniform_set: RID=rd.uniform_set_create(uniforms,shader,0)
    var pipeline: RID=rd.compute_pipeline_create(shader)
    if not uniform_set.is_valid() or not pipeline.is_valid():
        _fail("No GPU project pipeline")
        return
    var compute: int=rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute,pipeline)
    rd.compute_list_bind_uniform_set(compute,uniform_set,0)
    rd.compute_list_dispatch(compute,1,1,1)
    rd.compute_list_end()
    rd.submit()
    rd.sync()
    var got: PackedFloat32Array=rd.buffer_get_data(buffers[2]).to_float32_array()
    if got.size()!=20:
        _fail("Wrong reprojected sample count")
        return
    if absf(got[0]-64.0)>0.1 or absf(got[1]-64.0)>0.1 or absf(got[2]-6.0)>0.1 or got[3]<0.9:
        _fail("Center camera GPU reprojection is invalid: "+str(got.slice(0,4)))
        return
    if absf(got[4]-68.24)>0.2 or absf(got[5]-64.0)>0.1 or got[7]<0.9:
        _fail("Off-axis camera GPU projection invalid: "+str(got.slice(4,8)))
        return
    if got[11]>0.1 or got[15]>0.1:
        _fail("Out-of-frustum or invisible samples were incorrectly accepted")
        return
    if got[19]<0.9 or not (got[18]<got[2]):
        _fail("Linear depth is not responsive to source image depth")
        return
    for b in buffers:
        rd.free_rid(b)
    rd.free_rid(uniform_set)
    rd.free_rid(pipeline)
    rd.free_rid(shader)
    print("LIE-06 GPU PROJECT PASS Vulkan compute=true unproject3D=true target_perspective=true depth=true clipping=true")
    quit(0)

func _fail(message: String) -> void:
    printerr("LIE-06 GPU PROJECT FAIL ",message)
    quit(1)
