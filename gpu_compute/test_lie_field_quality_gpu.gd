extends "res://test_lie_light_field_gpu.gd"
const QualityShader=preload("res://shaders/lie_field_quality_area.glsl")
const QualityModel=preload("res://lie_field_quality_model.gd")
func shader_resource() -> RDShaderFile:return QualityShader
func surface_bridge() -> bool:return true
func submit(stages: Array,set_rid: RID) -> void:
    var expanded: Array=[]
    for row in stages:
        if row[0]==3:expanded.append_array([[3,row[1]*6,row[2]],[7,row[1],row[2]]])
        else:expanded.append(row)
    if OS.get_environment("LIE_QUALITY_TRACE")=="1":print("QUALITY SUBMIT ",expanded)
    if OS.get_environment("LIE_QUALITY_SYNC_STAGES")=="1":
        for row in expanded:
            print("QUALITY SINGLE ",row)
            super.submit([row],set_rid)
            print("QUALITY SINGLE DONE ",row)
    else:super.submit(expanded,set_rid)
    if OS.get_environment("LIE_QUALITY_TRACE")=="1":print("QUALITY SYNC ",expanded)
func case_extra_buffers(case: Dictionary) -> Dictionary:
    var n: int=case.model.patches.size();var areas: Array=[]
    for p in case.model.patches:areas.append(p.area)
    var data: Dictionary={27:QualityModel.packet(areas,case.model.get("field_quality",{}))}
    for pair in [[26,128],[28,n*8*6*32],[29,n*8*6*32],[30,n*8*6*16]]:
        var bytes:=PackedByteArray();bytes.resize(pair[1]);data[pair[0]]=bytes
    if case.has("emission_hex"):data[26]=str(case.emission_hex).hex_decode()
    return data
func run() -> void:
    var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/field-quality-reference.json"))
    rd=RenderingServer.create_local_rendering_device()
    if rd==null:printerr("Actual Vulkan required");quit(1);return
    var spirv: RDShaderSPIRV=shader_resource().get_spirv();shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
    if not pipeline.is_valid():printerr(spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE));quit(1);return
    var outputs: Dictionary={}
    var only: String=OS.get_environment("LIE_QUALITY_CASE")
    for name in fixture.cases:
        if only!="" and name!=only:continue
        print("QUALITY CASE ",name)
        outputs[name]=execute(fixture.cases[name],name)
        if outputs[name].is_empty():
            rd.free_rid(pipeline);rd.free_rid(shader);rd.free();quit(1);return
    if only!="":
        print("QUALITY TARGETED ",only," ","FAIL" if failed else "PASS")
        rd.free_rid(pipeline);rd.free_rid(shader);rd.free();quit(1 if failed else 0);return
    var a: PackedFloat32Array=outputs.paths_six;var b: PackedFloat32Array=outputs.paths_one
    check(a[3*4]>b[3*4]+.00001 and a[4*4]>b[4*4]+.00001,"one source retains both lateral reflection paths")
    check(b[5*4]>a[5*4]+.00001,"angular mean artifact removed from center")
    var restore: float=0.;var changed: float=0.
    for i in range(a.size()):
        restore=maxf(restore,absf(a[i]-outputs.paths_restored[i]));changed=maxf(changed,absf(a[i]-outputs.paths_blocked[i]))
    check(restore<1e-7 and changed>.00001,"moving occluder changes field and restoration is exact")
    var source_sum: float=0.
    for i in range(outputs.paths_two_sources.size()):source_sum=maxf(source_sum,absf(outputs.paths_two_sources[i]-outputs.paths_key_only[i]-outputs.paths_fill_only[i]))
    check(source_sum<1e-5,"quality field source superposition")
    var area_sum: float=0.
    for i in range(outputs.area_two_panels.size()):area_sum=maxf(area_sum,absf(outputs.area_two_panels[i]-outputs.area_key_only[i]-outputs.area_fill_only[i]))
    check(area_sum<1e-5,"eight physical panel channels preserve source superposition")
    report.merge({"checks":checks,"failed":failed,"device":rd.get_device_name(),"source_superposition_max_error":source_sum,"restoration_max_error":restore})
    var file:=FileAccess.open("res://field-quality-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    rd.free_rid(pipeline);rd.free_rid(shader);rd.free()
    print("FIELD QUALITY GPU ","FAIL" if failed else "PASS"," ",checks," cases ",fixture.cases.size());quit(1 if failed else 0)
