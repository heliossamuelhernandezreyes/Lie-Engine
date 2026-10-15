extends SceneTree
const ShaderFile=preload("res://shaders/lie_source_visibility_test.glsl")
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
    checks+=1
    if not value:failed=true;printerr("SOURCE VISIBILITY FAIL ",label)
func uniform(binding: int,rid: RID) -> RDUniform:
    var u:=RDUniform.new();u.binding=binding;u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.add_id(rid);return u
func run() -> void:
    var rd: RenderingDevice=RenderingServer.create_local_rendering_device()
    if rd==null:printerr("Actual Vulkan required");quit(1);return
    var shader: RID=rd.shader_create_from_spirv(ShaderFile.get_spirv());var pipeline: RID=rd.compute_pipeline_create(shader)
    if not pipeline.is_valid():printerr(ShaderFile.get_spirv().get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE));quit(1);return
    var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/source-visibility-reference.json"));var results: Dictionary={};var worst: float=0.
    for case in fixture["cases"]:
        var count: int=case["expected"].size();var zero:=PackedByteArray();zero.resize(count*4)
        var data: Array=[]
        for key in ["bank_hex","nodes_hex","leaves_hex","scene_hex","queries_hex"]:data.append(str(case[key]).hex_decode())
        data.append(zero);var rids: Array[RID]=[];var uniforms: Array[RDUniform]=[]
        for i in range(data.size()):rids.append(rd.storage_buffer_create(data[i].size(),data[i]));uniforms.append(uniform(i,rids[-1]))
        var set_rid: RID=rd.uniform_set_create(uniforms,shader,0);check(set_rid.is_valid(),case["name"]+" actual uniform set")
        var list: int=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set_rid,0);rd.compute_list_set_push_constant(list,PackedInt32Array([count]).to_byte_array(),4);rd.compute_list_dispatch(list,ceili(float(count)/64.),1,1);rd.compute_list_end();rd.submit();rd.sync()
        var values: PackedFloat32Array=rd.buffer_get_data(rids[-1]).to_float32_array();var error: float=0.
        for i in range(count):
            error=maxf(error,absf(values[i]-float(case["expected"][i])));check(is_finite(values[i]) and values[i]>=0. and values[i]<=1.,case["name"]+" finite passive visibility")
            check(values[i]==values[0],case["name"]+" camera-independent query")
        check(error<.0001,case["name"]+" exhaustive float64 agreement");worst=maxf(worst,error);results[case["name"]]={"error":error,"visibility":Array(values),"reference":case["expected"]}
        rd.free_rid(set_rid)
        for rid in rids:rd.free_rid(rid)
    var file:=FileAccess.open("res://source-visibility-native.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"max_error":worst,"cases":results,"device":rd.get_device_name(),"physical_android_tested":false},"  ",true,true));file.close()
    rd.free_rid(pipeline);rd.free_rid(shader);rd.free();print("SOURCE VISIBILITY GPU ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
