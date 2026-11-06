extends "res://test_lie_light_field_gpu.gd"
## Diagnostic: exact same scene on the accepted v1 kernel, unchanged buffers.
func run() -> void:
    var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/field-quality-reference.json"))
    rd=RenderingServer.create_local_rendering_device()
    if rd==null:quit(1);return
    var spirv: RDShaderSPIRV=shader_resource().get_spirv();shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
    if not pipeline.is_valid():printerr(spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE));quit(1);return
    print("QUALITY LEGACY SAME SCENE BEGIN")
    var result: PackedFloat32Array=execute(fixture.cases.paths_one,"same_scene_v1")
    check(not result.is_empty(),"accepted v1 same-scene execution")
    print("QUALITY LEGACY SAME SCENE ","FAIL" if failed else "PASS"," ",checks)
    rd.free_rid(pipeline);rd.free_rid(shader);rd.free();quit(1 if failed else 0)
