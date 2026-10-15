extends SceneTree
const ShaderFile=preload("res://shaders/lie_filter_test.glsl")
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
    checks+=1
    if not value:failed=true;printerr("FILTER FAIL ",label)
func run() -> void:
    var rd:=RenderingServer.create_local_rendering_device()
    if rd==null:quit(1);return
    var shader: RID=rd.shader_create_from_spirv(ShaderFile.get_spirv());var pipeline: RID=rd.compute_pipeline_create(shader)
    if not pipeline.is_valid():printerr(ShaderFile.get_spirv().get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE));quit(1);return
    var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/filter-reference.json"));var results: Dictionary={}
    for name in fixture["cases"]:
        var case: Dictionary=fixture["cases"][name];var cfg:=PackedInt32Array([0,0,5,5]).to_byte_array();cfg.append_array(PackedFloat32Array([.5,0,0,0]).to_byte_array())
        var zero:=PackedByteArray();zero.resize(25*8*4)
        var buffers: Array[RID]=[];var uniforms: Array[RDUniform]=[];var payloads: Array=[str(case["acc_hex"]).hex_decode(),str(case["owners_hex"]).hex_decode(),str(case["projection_hex"]).hex_decode(),cfg,zero]
        for binding in range(5):
            var rid: RID=rd.storage_buffer_create(payloads[binding].size(),payloads[binding]);buffers.append(rid)
            var u:=RDUniform.new();u.binding=binding;u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.add_id(rid);uniforms.append(u)
        var set_rid: RID=rd.uniform_set_create(uniforms,shader,0);check(set_rid.is_valid(),name+" actual descriptor set")
        var list: int=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set_rid,0);rd.compute_list_dispatch(list,1,1,1);rd.compute_list_end();rd.submit();rd.sync()
        var output: PackedFloat32Array=rd.buffer_get_data(buffers[4]).to_float32_array();var worst: float=0
        for i in range(output.size()):worst=maxf(worst,absf(output[i]-float(case["expected"][i])))
        check(worst<.0006,name+" float64 reference and half packet");results[name]={"max_error":worst,"center":Array(output.slice(12*8,13*8))}
        if name=="open_hole":check(output[12*8]==0. and output[12*8+7]==0.,"real hole remains empty")
        rd.free_rid(set_rid)
        for rid in buffers:rd.free_rid(rid)
    var file:=FileAccess.open("res://filter-native.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"device":rd.get_device_name(),"cases":results},"  ",true,true));file.close()
    rd.free_rid(pipeline);rd.free_rid(shader);rd.free();print("FILTER ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
