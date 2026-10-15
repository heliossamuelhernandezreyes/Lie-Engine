extends "res://test_lie_light_field_gpu.gd"
const AreaField=preload("res://shaders/lie_area_field.glsl")
func shader_resource() -> RDShaderFile:return AreaField
func surface_bridge() -> bool:return true
func case_extra_buffers(case: Dictionary) -> Dictionary:return {26:str(case["emission_hex"]).hex_decode()}
func run() -> void:
    var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/area-field-reference.json"))
    rd=RenderingServer.create_local_rendering_device()
    if rd==null:printerr("Actual Vulkan required");quit(1);return
    var spirv: RDShaderSPIRV=shader_resource().get_spirv();shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
    if not pipeline.is_valid():printerr(spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE));quit(1);return
    var outputs: Dictionary={}
    for name in fixture["cases"]:outputs[name]=execute(fixture["cases"][name],name)
    var superposition: float=0.;var legacy: float=0.
    for i in range(outputs["two_panels"].size()):
        superposition=maxf(superposition,absf(outputs["two_panels"][i]-outputs["key_only"][i]-outputs["fill_only"][i]))
        legacy=maxf(legacy,absf(outputs["two_panels"][i]-outputs["legacy_merged"][i]))
    check(superposition<.00001,"actual GPU source superposition");check(legacy>.000001,"area channel directions differ from merged approximation")
    var back_energy: float=0.
    for value in outputs["backwards"]:back_energy=maxf(back_energy,absf(value))
    check(back_energy<.000001,"one-sided panels facing backwards emit zero")
    report.merge({"checks":checks,"failed":failed,"device":rd.get_device_name(),"source_superposition_max_error":superposition,"legacy_merged_max_difference":legacy})
    var file:=FileAccess.open("res://area-field-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    rd.free_rid(pipeline);rd.free_rid(shader);rd.free()
    print("AREA FIELD GPU ","FAIL" if failed else "PASS"," ",checks," cases ",fixture["cases"].size());quit(1 if failed else 0)
