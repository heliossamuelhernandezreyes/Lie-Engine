extends SceneTree
const ShaderFile=preload("res://shaders/lie_pages_test.glsl")
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("PAGE GPU FAIL ",label)
func uniform(binding: int,rid: RID) -> RDUniform:
    var u:=RDUniform.new();u.binding=binding;u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.add_id(rid);return u
func run() -> void:
    var rd: RenderingDevice=RenderingServer.create_local_rendering_device()
    if rd==null:printerr("Actual Vulkan required");quit(1);return
    var shader: RID=rd.shader_create_from_spirv(ShaderFile.get_spirv());var pipeline: RID=rd.compute_pipeline_create(shader)
    if not pipeline.is_valid():printerr(ShaderFile.get_spirv().get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE));quit(1);return
    var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/spatial-pages-reference.json"));var results: Dictionary={};var cells: int=0;var fallbacks: int=0
    for case in fixture["cases"]:
        var count: int=case["expected"].size();var control:=PackedByteArray();control.resize(256+count*4);control.encode_u32(8,1);control.encode_u32(12,count)
        var zero:=PackedByteArray();zero.resize(count*4)
        var data: Dictionary={0:str(case["bank_hex"]).hex_decode(),1:str(case["nodes_hex"]).hex_decode(),2:str(case["leaves_hex"]).hex_decode(),3:str(case["scene_hex"]).hex_decode(),4:str(case["queries_hex"]).hex_decode(),5:zero,37:str(case["pages_hex"]).hex_decode(),39:control}
        var rids: Dictionary={};var uniforms: Array[RDUniform]=[]
        for binding in data:rids[binding]=rd.storage_buffer_create(data[binding].size(),data[binding]);uniforms.append(uniform(binding,rids[binding]))
        var set_rid: RID=rd.uniform_set_create(uniforms,shader,0);check(set_rid.is_valid(),case["name"]+" bindings")
        var reference:=PackedFloat32Array();var error: float=0.;var difference: float=0.
        for enabled in [false,true]:
            rd.buffer_update(rids[39],16,4,PackedInt32Array([1 if enabled else 0]).to_byte_array())
            var list: int=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set_rid,0);rd.compute_list_dispatch(list,ceili(float(count)/64.),1,1);rd.compute_list_end();rd.submit();rd.sync()
            var values: PackedFloat32Array=rd.buffer_get_data(rids[5]).to_float32_array()
            if not enabled:reference=values
            for i in range(count):
                error=maxf(error,absf(values[i]-float(case["expected"][i])));difference=maxf(difference,absf(values[i]-reference[i]))
                check(is_finite(values[i]) and values[i]>=0. and values[i]<=1.,case["name"]+" finite passive visibility")
        var stats: PackedInt32Array=rd.buffer_get_data(rids[39],80,16).to_int32_array();cells+=stats[1];fallbacks+=stats[3]
        check(error<.0001 and difference<.000001,case["name"]+" independent exhaustive oracle and original BLAS")
        if case["name"]=="dense_page_fallback":check(stats[3]>0,"dense page falls back instead of dropping candidates")
        results[case["name"]]={"oracle_max_error":error,"bvh_max_difference":difference,"page_rays":stats[0],"cells":stats[1],"disk_tests":stats[2],"fallbacks":stats[3],"queries":count}
        rd.free_rid(set_rid)
        for rid in rids.values():rd.free_rid(rid)
    check(cells>0 and fallbacks>0,"real page traversal and conservative fallback exercised")
    var file:=FileAccess.open("res://pages-native.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"cases":results,"device":rd.get_device_name(),"physical_android_tested":false},"  ",true,true));file.close()
    rd.free_rid(pipeline);rd.free_rid(shader);rd.free();print("PAGE GPU ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
