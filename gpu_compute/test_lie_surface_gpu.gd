extends SceneTree
const ShaderFile=preload("res://shaders/lie_surface_test.glsl")
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
    checks+=1
    if not value:failed=true;printerr("SURFACE GPU FAIL ",label)
func uniform(binding: int,rid: RID) -> RDUniform:
    var u:=RDUniform.new();u.binding=binding;u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.add_id(rid);return u
func run() -> void:
    var rd: RenderingDevice=RenderingServer.create_local_rendering_device()
    if rd==null:printerr("Actual Vulkan required");quit(1);return
    var shader: RID=rd.shader_create_from_spirv(ShaderFile.get_spirv());var pipeline: RID=rd.compute_pipeline_create(shader)
    if not pipeline.is_valid():printerr(ShaderFile.get_spirv().get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE));quit(1);return
    var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/surface-reference.json"));var results: Dictionary={}
    for case in fixture["cases"]:
        var zeros:=PackedByteArray();zeros.resize(64)
        var lights:=PackedInt32Array([1,1,16,1]).to_byte_array();lights.append_array(PackedFloat32Array([0.,0.,1.,6.,4.,2.,1.,.0025]).to_byte_array())
        var data: Array=[str(case["header_hex"]).hex_decode(),str(case["planes_hex"]).hex_decode(),zeros,lights]
        var rids: Array[RID]=[];var uniforms: Array[RDUniform]=[]
        for i in range(4):rids.append(rd.storage_buffer_create(data[i].size(),data[i]));uniforms.append(uniform(i,rids[-1]))
        var set_rid: RID=rd.uniform_set_create(uniforms,shader,0);check(set_rid.is_valid(),case["name"]+" actual uniform set")
        var list: int=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set_rid,0);rd.compute_list_dispatch(list,1,1,1);rd.compute_list_end();rd.submit();rd.sync()
        var values: PackedFloat32Array=rd.buffer_get_data(rids[2]).to_float32_array();var error: float=absf(values[0]-float(case["visibility"]))
        check(error<.0001,case["name"]+" exhaustive float64 oracle: "+str(values[0]))
        for k in range(3):
            check(absf(values[4+k]-float([.05,.075,.1][k]))<.000001,"contact attenuates direct only")
            check(absf(values[8+k]-.125)<.000001,"detail uses gated local direct")
            var expected: float=float([4.,2.,1.][k])*pow(1.-pow(1./6.,4.),2.)/(4.*PI)
            check(absf(values[12+k]-expected)<.000001,"point source agrees with analytic equation")
        results[case["name"]]={"visibility":values[0],"oracle":case["visibility"],"error":error}
        rd.free_rid(set_rid)
        for rid in rids:rd.free_rid(rid)
    var file:=FileAccess.open("res://surface-native.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"cases":results,"device":rd.get_device_name(),"physical_android_tested":false},"  "));file.close()
    rd.free_rid(pipeline);rd.free_rid(shader);rd.free();print("SURFACE GPU ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
