extends SceneTree
## Full LIE-07 Vulkan test: 4 source transforms -> projection -> z-min
## -> confidence fusion -> GPU storage texture, no intermediate CPU readback.
## Uses a local RenderingDevice: NOT presented inside the main game viewport.
const SHADER_PATH := "res://shaders/lie07_pipeline.glsl"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var rd: RenderingDevice = RenderingServer.create_local_rendering_device()
    if rd == null:
        _fail("No Vulkan RenderingDevice")
        return
    var file: RDShaderFile = load(SHADER_PATH) as RDShaderFile
    if file == null:
        _fail("No imported LIE-07 shader")
        return
    var code: RDShaderSPIRV = file.get_spirv()
    var err: String = code.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
    if err != "":
        _fail("LIE-07 shader compile: " + err)
        return
    var shader: RID = rd.shader_create_from_spirv(code)
    var pipeline: RID = rd.compute_pipeline_create(shader)
    if not shader.is_valid() or not pipeline.is_valid():
        _fail("Invalid Vulkan compute pipeline")
        return

    var width := 16
    var height := 16
    # First and third samples project to pixel (8,8), from DIFFERENT
    # source positions. Second is farther; fourth is closer but zero-normal
    # confidence, so it must not write z or contaminate the output.
    # Fifth projects to (9,8); sixth is outside the view; seventh invalid.
    var samples := PackedFloat32Array([
        0.5,0.5,0.5,1, 0.5,0.5,0.5,1, 1.0,0.5,0.5,1,
        0.0,0.5,0.5,1, 0.7,0.5,0.5,1, 9,0.5,0.5,1,
        0.5,0.5,0.5,0
    ])
    var colors := PackedFloat32Array([
        1,0,0,1, 0,0,1,1, 0,1,0,1,
        1,1,0,1, 0,1,1,1, 1,1,1,1,
        1,0,1,1
    ])
    var attrs := PackedFloat32Array([
        0,1,0.25,0, 1,1,1,0, 2,1,0.75,0,
        3,0,1,0, 0,1,1,0, 0,1,1,0,
        0,1,1,0
    ])
    var cameras := PackedFloat32Array()
    for view in range(4):
        var origin_x := 0.0
        if view == 2:
            origin_x = -1.0
        if view == 3:
            origin_x = 1.0
        var source_z := 1.0
        if view == 1:
            source_z = 2.0
        if view == 3:
            source_z = 0.5
        cameras.append_array(PackedFloat32Array([
            origin_x,0,3,0, 1,0,0,0, 0,1,0,0, 0,0,-1,0,
            0,0,6,0, 1,0,0,0, 0,1,0,0, 0,0,-1,0,
            2,source_z,source_z,0, 0.57735026919,1,0.1,100
        ]))
    var projected := PackedFloat32Array()
    projected.resize(samples.size())
    var empty_depth := PackedInt32Array()
    empty_depth.resize(width*height)
    var empty_sum := PackedInt32Array()
    empty_sum.resize(width*height*4)
    var buffers: Array[RID] = [
        rd.storage_buffer_create(samples.to_byte_array().size(),samples.to_byte_array()),
        rd.storage_buffer_create(colors.to_byte_array().size(),colors.to_byte_array()),
        rd.storage_buffer_create(attrs.to_byte_array().size(),attrs.to_byte_array()),
        rd.storage_buffer_create(cameras.to_byte_array().size(),cameras.to_byte_array()),
        rd.storage_buffer_create(projected.to_byte_array().size(),projected.to_byte_array()),
        rd.storage_buffer_create(empty_depth.to_byte_array().size(),empty_depth.to_byte_array()),
        rd.storage_buffer_create(empty_sum.to_byte_array().size(),empty_sum.to_byte_array()),
        rd.storage_buffer_create(16,PackedInt32Array([width,height,1,0]).to_byte_array())
    ]
    var fmt := RDTextureFormat.new()
    fmt.width = width
    fmt.height = height
    fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
    var texture: RID = rd.texture_create(fmt,RDTextureView.new(),[])
    if not texture.is_valid():
        _fail("GPU storage texture invalid")
        return
    var uniforms: Array[RDUniform] = []
    for binding in range(buffers.size()):
        var u := RDUniform.new()
        u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u.binding = binding
        u.add_id(buffers[binding])
        uniforms.append(u)
    var image_uniform := RDUniform.new()
    image_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
    image_uniform.binding = 8
    image_uniform.add_id(texture)
    uniforms.append(image_uniform)
    var uniform_set: RID = rd.uniform_set_create(uniforms,shader,0)
    if not uniform_set.is_valid():
        _fail("Uniform set invalid")
        return

    var list: int = rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(list,pipeline)
    rd.compute_list_bind_uniform_set(list,uniform_set,0)
    for stage in range(5):
        var push := PackedInt32Array([stage]).to_byte_array()
        rd.compute_list_set_push_constant(list,push,push.size())
        var threads: int = width*height if stage == 0 or stage == 4 else samples.size()/4
        rd.compute_list_dispatch(list,int(ceil(float(threads)/64.0)),1,1)
        if stage < 4:
            rd.compute_list_add_barrier(list)
    rd.compute_list_end()
    rd.submit()
    rd.sync() # Only here, in the test, to validate the FINAL image.
    var result: PackedFloat32Array = rd.texture_get_data(texture,0).to_float32_array()
    if result.size() != width*height*4:
        _fail("Invalid GPU RGBA32F image size " + str(result.size()))
        return
    var center: int = (8*width+8)*4
    var right: int = (8*width+9)*4
    var blank: int = (0*width+0)*4
    if not _near(result[center],0.25) or not _near(result[center+1],0.75) or not _near(result[center+2],0.0) or not _near(result[center+3],1.0):
        _fail("Four-camera depth/weight test failed at center: "+str(result.slice(center,center+4)))
        return
    if not _near(result[right],0.0) or not _near(result[right+1],1.0) or not _near(result[right+2],1.0) or not _near(result[right+3],1.0):
        _fail("Off-center 3D projection wrong: "+str(result.slice(right,right+4)))
        return
    if not _near(result[blank],0.0) or not _near(result[blank+3],0.0):
        _fail("Background must remain transparent")
        return
    rd.free_rid(uniform_set)
    rd.free_rid(texture)
    for rid in buffers:
        rd.free_rid(rid)
    rd.free_rid(pipeline)
    rd.free_rid(shader)
    print("LIE-07 GPU PASS four_views=true depth_test=true normal_reject=true color_blend=true gpu_image=true no_intermediate_readback=true")
    quit(0)

func _near(value: float, expected: float) -> bool:
    return absf(value-expected) < 0.03

func _fail(message: String) -> void:
    printerr("LIE-07 GPU FAIL: ",message)
    quit(1)
