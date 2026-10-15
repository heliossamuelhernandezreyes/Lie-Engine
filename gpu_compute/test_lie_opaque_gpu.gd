extends SceneTree
const Kernel=preload("res://shaders/lie_opaque_test.glsl")
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var rd: RenderingDevice=RenderingServer.create_local_rendering_device()
    if rd==null:printerr("Actual Vulkan required");quit(1);return
    var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/opaque-reference.json"))
    var inputs:=PackedFloat32Array()
    for case in fixture["cases"]:inputs.append_array(PackedFloat32Array(case["input"]))
    var shader: RID=rd.shader_create_from_spirv(Kernel.get_spirv());var pipeline: RID=rd.compute_pipeline_create(shader)
    var src: RID=rd.storage_buffer_create(inputs.size()*4,inputs.to_byte_array());var dst: RID=rd.storage_buffer_create(fixture["cases"].size()*16)
    var uniforms: Array[RDUniform]=[]
    for index in range(2):
        var u:=RDUniform.new();u.binding=index;u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.add_id(src if index==0 else dst);uniforms.append(u)
    var set_rid: RID=rd.uniform_set_create(uniforms,shader,0)
    if not pipeline.is_valid() or not set_rid.is_valid():printerr("Opaque kernel compile/bind failed");quit(1);return
    var list: int=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set_rid,0)
    rd.compute_list_set_push_constant(list,PackedInt32Array([fixture["cases"].size(),0,0,0]).to_byte_array(),16);rd.compute_list_dispatch(list,ceili(fixture["cases"].size()/64.),1,1);rd.compute_list_end();rd.submit();rd.sync()
    var values: PackedFloat32Array=rd.buffer_get_data(dst).to_float32_array();var failed: bool=false;var worst: float=0;var rows: Array=[]
    for i in range(fixture["cases"].size()):
        var case: Dictionary=fixture["cases"][i];var delta: float=0
        for c in range(4):
            var d: float=absf(values[i*4+c]-float(case["expected"][c]));delta=maxf(delta,d);worst=maxf(worst,d)
            if not is_finite(values[i*4+c]) or d>maxf(.00005,absf(float(case["expected"][c]))*.0002):failed=true;printerr("OPAQUE FAIL ",case["name"]," channel ",c," ",d)
        rows.append({"case":case["name"],"expected":case["expected"],"actual":Array(values.slice(i*4,i*4+4)),"max":delta})
    var file:=FileAccess.open("res://opaque-native.json",FileAccess.WRITE);file.store_string(JSON.stringify({"cases":rows,"failed":failed,"max":worst,"device":rd.get_device_name(),"physical_android_tested":false},"  ",true,true));file.close()
    for rid in [set_rid,src,dst,pipeline,shader]:rd.free_rid(rid)
    rd.free();print("OPAQUE GPU ","FAIL" if failed else "PASS"," ",fixture["cases"].size()," max ",worst);quit(1 if failed else 0)
