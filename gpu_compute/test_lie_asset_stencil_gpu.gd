extends SceneTree
const ShaderFile=preload("res://shaders/lie_asset_stencil_test.glsl")
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/asset-light-reference.json"))
    var queries:=PackedFloat32Array();var packet:=PackedByteArray()
    for i in range(data["points"].size()):
        queries.append_array(PackedFloat32Array([data["points"][i][0],data["points"][i][1],data["points"][i][2],data["nodes"][i]]))
    for i in range(data["positions"].size()):
        var p: Array=data["positions"][i];var n: Array=data["normals"][i];var g: Array=data["groups"][i]
        packet.append_array(PackedFloat32Array([p[0],p[1],p[2],data["areas"][i],n[0],n[1],n[2],0.]).to_byte_array())
        packet.append_array(PackedInt32Array([g[0],g[1],0,0]).to_byte_array())
    var rd: RenderingDevice=RenderingServer.create_local_rendering_device()
    if rd==null:printerr("ASSET STENCIL no Vulkan RD");quit(1);return
    var shader: RID=rd.shader_create_from_spirv(ShaderFile.get_spirv());var pipeline: RID=rd.compute_pipeline_create(shader)
    var Q: int=data["points"].size();var N: int=data["positions"].size()
    var buffers: Array[RID]=[rd.storage_buffer_create(queries.size()*4,queries.to_byte_array()),rd.storage_buffer_create(packet.size(),packet),rd.storage_buffer_create(Q*N*4)]
    var uniforms: Array[RDUniform]=[]
    for i in range(3):
        var uniform:=RDUniform.new();uniform.binding=i;uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;uniform.add_id(buffers[i]);uniforms.append(uniform)
    var set_rid: RID=rd.uniform_set_create(uniforms,shader,0);var list: int=rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set_rid,0);rd.compute_list_set_push_constant(list,PackedInt32Array([Q,N,0,0]).to_byte_array(),16);rd.compute_list_dispatch(list,int(ceil(float(Q)/64.)),1,1);rd.compute_list_end();rd.submit();rd.sync()
    var result: PackedFloat32Array=rd.buffer_get_data(buffers[2]).to_float32_array();var max_error: float=0.;var okay: bool=true
    for i in range(Q):
        var sum: float=0.
        for j in range(N):
            var value: float=result[i*N+j];max_error=maxf(max_error,absf(value-float(data["expected"][i][j])));okay=okay and is_finite(value) and value>=0.;sum+=value
        okay=okay and absf(sum-1.)<.00001
    okay=okay and max_error<.00001
    var report: Dictionary={"queries":Q,"source_types":2,"gpu_cpu_max_error":max_error,"okay":okay,"banks":data["bank_sha256"],"device":rd.get_device_name(),"physical_android_tested":false}
    var file:=FileAccess.open("res://asset-stencil-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
    rd.free_rid(set_rid)
    for rid in buffers:rd.free_rid(rid)
    rd.free_rid(pipeline);rd.free_rid(shader);rd.free()
    print("ASSET STENCIL ","PASS " if okay else "FAIL ",Q," queries, max=",max_error);quit(0 if okay else 1)
