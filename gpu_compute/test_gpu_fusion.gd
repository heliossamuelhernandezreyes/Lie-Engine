extends SceneTree
# Mandatory Vulkan compute execution test, never skip unavailable hardware.
# Run using the dedicated gpu_compute/project.godot (Forward+) under Vulkan.
func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var rd: RenderingDevice = RenderingServer.create_local_rendering_device()
    if rd == null:
        _fail("Vulkan local RenderingDevice unavailable; compute not executed")
        return
    var file: RDShaderFile = load("res://shaders/depth_fusion.glsl") as RDShaderFile
    if file == null:
        _fail("Compute shader resource not imported")
        return
    var spirv: RDShaderSPIRV = file.get_spirv()
    var errors: String = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
    if errors != "":
        _fail(errors)
        return
    var shader: RID = rd.shader_create_from_spirv(spirv)
    if not shader.is_valid():
        _fail("Unable to instantiate GPU compute shader")
        return

    # 4 pixels * 4 views = 16 samples. Each view contributes 4 RGBA floats.
    var colors := PackedFloat32Array()
    var props := PackedFloat32Array()
    func_add_fixture(colors, props, [
        # pixel 0: nearer red wins against far blue (even if blue has high weight).
        [[1,0,0,1,1,1,1,1],[0,0,1,1,3,1,1,1]],
        # pixel 1: equal depth, red 25% blue 75% confidence-weighted crossfade.
        [[1,0,0,1,2,1,0.25,1],[0,0,1,1,2,1,0.75,1]],
        # pixel 2: no foreground.
        [],
        # pixel 3: closer green wins against farther red.
        [[0,1,0,1,1.5,1,1,1],[1,0,0,1,2.5,1,1,1]],
        # pixel 4: at SAME depth a backfacing red surface must not
        # overpower a properly facing green surface.
        [[1,0,0,1,1.0,0,1,1],[0,1,0,1,1.0,1,1,1]]
    ])
    var input0: RID = rd.storage_buffer_create(colors.to_byte_array().size(), colors.to_byte_array())
    var input1: RID = rd.storage_buffer_create(props.to_byte_array().size(), props.to_byte_array())
    var output: PackedFloat32Array = PackedFloat32Array()
    output.resize(5 * 4)
    var output_buffer: RID = rd.storage_buffer_create(output.to_byte_array().size(), output.to_byte_array())
    var uniforms := []
    for i in range(3):
        var uniform := RDUniform.new()
        uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        uniform.binding = i
        uniform.add_id([input0,input1,output_buffer][i])
        uniforms.append(uniform)
    var uniform_set: RID = rd.uniform_set_create(uniforms, shader, 0)
    var pipeline: RID = rd.compute_pipeline_create(shader)
    if not uniform_set.is_valid() or not pipeline.is_valid():
        _fail("Cannot build GPU compute pipeline")
        return
    var compute: int = rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute, pipeline)
    rd.compute_list_bind_uniform_set(compute, uniform_set, 0)
    rd.compute_list_dispatch(compute, 1, 1, 1)
    rd.compute_list_end()
    rd.submit()
    rd.sync()
    var got: PackedFloat32Array = rd.buffer_get_data(output_buffer).to_float32_array()
    var expected: PackedFloat32Array = PackedFloat32Array([
        1,0,0,1, 0.25,0,0.75,1, 0,0,0,0, 0,1,0,1, 0,1,0,1
    ])
    if got.size() != expected.size():
        _fail("Incorrect GPU output length")
        return
    for i in range(expected.size()):
        if absf(got[i] - expected[i]) > 0.03:
            _fail("GPU disagreement index %d expected %.3f got %.3f" % [i,expected[i],got[i]])
            return
    rd.free_rid(uniform_set)
    rd.free_rid(pipeline)
    rd.free_rid(shader)
    rd.free_rid(input0)
    rd.free_rid(input1)
    rd.free_rid(output_buffer)
    print("LIE-06 GPU PASS actual_compute=true depth_wins=true confidence_crossfade=true normal_rejection=true empty_alpha=true")
    quit(0)

func func_add_fixture(colors: PackedFloat32Array, props: PackedFloat32Array, pixels: Array) -> void:
    for pixel in pixels:
        for sample_id in range(4):
            var v: Array = pixel[sample_id] if sample_id < pixel.size() else [0,0,0,0,0,0,0,0]
            for i in range(4):
                colors.append(float(v[i]))
            for i in range(4,8):
                props.append(float(v[i]))

func _fail(message: String) -> void:
    printerr("LIE-06 GPU FAIL ", message)
    quit(1)
