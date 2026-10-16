extends SceneTree
const ShaderFile=preload("res://shaders/lie_compact_shadow_test.glsl")
var checks: int=0
var failed: bool=false
var rd: RenderingDevice
var shader: RID
var pipeline: RID
var set_rid: RID
var rids: Dictionary={}
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("COMPACT REFERENCE FAIL ",label)
func uniform(binding: int,rid: RID) -> RDUniform:
    var u:=RDUniform.new();u.binding=binding;u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.add_id(rid);return u
func solve(query: PackedByteArray,enabled: bool) -> Dictionary:
    rd.buffer_update(rids[4],0,query.size(),query)
    rd.buffer_update(rids[39],0,16,PackedInt32Array([0,int(enabled),1,8]).to_byte_array())
    var zero:=PackedByteArray();zero.resize(32);rd.buffer_update(rids[39],64,32,zero)
    var list: int=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set_rid,0);rd.compute_list_dispatch(list,1,1,1);rd.compute_list_end();rd.submit();rd.sync()
    return {"values":Array(rd.buffer_get_data(rids[5]).to_float32_array()),"stats":Array(rd.buffer_get_data(rids[39],64,32).to_int32_array()),"hints":Array(rd.buffer_get_data(rids[39],256,32).to_int32_array())}
func query_bytes(case: Dictionary,light: Array,reach: float=.025,bias: float=.0003) -> PackedByteArray:
    var p: Array=case["projection"];var result:=PackedByteArray()
    for l in range(8):
        result.append_array(PackedFloat32Array([p[0],p[1],p[2],reach,p[4],p[5],p[6],bias,light[0],light[1],light[2],0.]).to_byte_array())
        result.append_array(PackedInt32Array([int(p[10]),int(p[11]),0,0]).to_byte_array())
    return result
func run() -> void:
    rd=RenderingServer.create_local_rendering_device()
    if rd==null:printerr("Actual Vulkan required");quit(1);return
    shader=rd.shader_create_from_spirv(ShaderFile.get_spirv());pipeline=rd.compute_pipeline_create(shader)
    if not pipeline.is_valid():printerr(ShaderFile.get_spirv().get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE));quit(1);return
    var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/compact-shadow-reference.json"));var evidence: Dictionary={};var total_hits: int=0
    for case in fixture["cases"]:
        var data: Dictionary={0:str(case["bank_hex"]).hex_decode(),1:str(case["nodes_hex"]).hex_decode(),2:str(case["leaves_hex"]).hex_decode(),3:str(case["scene_hex"]).hex_decode(),4:query_bytes(case,case["light"]),5:PackedByteArray(),39:PackedByteArray()}
        data[5].resize(32);data[39].resize(288)
        rids={};var uniforms: Array[RDUniform]=[]
        for binding in data:rids[binding]=rd.storage_buffer_create(data[binding].size(),data[binding]);uniforms.append(uniform(binding,rids[binding]))
        set_rid=rd.uniform_set_create(uniforms,shader,0);check(set_rid.is_valid(),case["name"]+" bindings")
        var cold: Dictionary=solve(query_bytes(case,case["light"]),true)
        for value in cold["values"]:check(absf(value-case["expected"][0])<.00001,case["name"]+" cold float64")
        var same: Dictionary=solve(query_bytes(case,case["light"]),true);check(same["values"]==cold["values"],"witness exact at original light")
        total_hits+=same["stats"][1]
        var tiny: Array=case["light"].duplicate();tiny[0]+=.00001;tiny[1]-=.00001
        var nearby: Dictionary=solve(query_bytes(case,tiny),true);var exact: Dictionary=solve(query_bytes(case,tiny),false)
        check(nearby["values"]==exact["values"],"small displacement revalidates against full traversal");total_hits+=nearby["stats"][1]
        var moved: Dictionary=solve(query_bytes(case,case["moved_light"]),true)
        for value in moved["values"]:check(absf(value-case["moved_expected"])<.00001,"moved light escapes old blocker and matches oracle")
        var metric: Dictionary=solve(query_bytes(case,case["light"],.02,.00033),true)
        for value in metric["values"]:check(absf(value-case["metric_expected"])<.00001,"metric changes retest geometry")
        rd.buffer_update(rids[39],256,32,PackedInt32Array([-1,-1,-1,-1,-1,-1,-1,-1]).to_byte_array())
        var stale: Dictionary=solve(query_bytes(case,case["light"]),true)
        check(stale["values"]==cold["values"],"out-of-domain stale candidates rejected")
        evidence[case["name"]]={"cold":cold,"same":same,"nearby":nearby,"moved":moved,"metric":metric,"stale":stale}
        rd.free_rid(set_rid)
        for rid in rids.values():rd.free_rid(rid)
    check(total_hits>0,"actual certified blockers skip full traversal")
    var file:=FileAccess.open("res://compact-reference-native.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"cases":evidence,"certified_hits":total_hits,"device":rd.get_device_name(),"physical_android_tested":false},"  ",true,true));file.close()
    rd.free_rid(pipeline);rd.free_rid(shader);rd.free();print("COMPACT REFERENCE GPU ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
