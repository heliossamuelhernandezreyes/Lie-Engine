extends SceneTree
## Actual common runtime shader on Vulkan, checked against float64 fixtures.
const ShaderFile=preload("res://shaders/lie_light_field.glsl")
const Model=preload("res://lie11_model.gd")
const Optics=preload("res://lie13_optics_model.gd")
var checks: int=0
var failed: bool=false
var rd: RenderingDevice
var shader: RID
var pipeline: RID
var report: Dictionary={"cases":{},"max_error":0.,"physical_android_tested":false}
func shader_resource() -> RDShaderFile:return ShaderFile
func surface_bridge() -> bool:return false
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
    checks+=1
    if not value:failed=true;printerr("FIELD GPU FAIL ",label)
func uniform(binding: int,rid: RID,image: bool=false) -> RDUniform:
    var u:=RDUniform.new();u.binding=binding;u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if image else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.add_id(rid);return u
func submit(stages: Array,set_rid: RID) -> void:
    var list: int=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set_rid,0)
    for row in stages:
        rd.compute_list_set_push_constant(list,PackedInt32Array([row[0],row[2],0,0]).to_byte_array(),16)
        rd.compute_list_dispatch(list,ceili(float(row[1])/64.),1,1);rd.compute_list_add_barrier(list)
    rd.compute_list_end();rd.submit();rd.sync()
func totals(data: PackedFloat32Array,n: int,lights: int) -> Array:
    var out: Array=[]
    for l in range(lights):
        var sum:=Vector3.ZERO
        for i in range(n):var j: int=(l*n+i)*4;sum+=Vector3(data[j],data[j+1],data[j+2])
        out.append([sum.x,sum.y,sum.z])
    return out
func execute(case: Dictionary,name: String) -> PackedFloat32Array:
    var model: Dictionary=case["model"];var n: int=model["patches"].size();var lights: int=model["lights"].size();var sep: bool=case["separate"]
    var packets: Dictionary={}
    for key in case["sources_hex"]:packets[key]=str(case["sources_hex"][key]).hex_decode()
    var dims:=PackedInt32Array([n,lights,model["bounces"],model.get("blockers",[]).size()]).to_byte_array()
    var policy: Dictionary=model.get("secondary_radii",{})
    dims.append_array(PackedFloat32Array([.0025,0.,float(model.get("triangles",[]).size()),Model.radius_mode(policy)]).to_byte_array())
    dims.append_array(PackedFloat32Array([policy.get("radius_max",1.),policy.get("radius_decay",1.),Model.radius_reference(policy),0.]).to_byte_array())
    var optic: PackedByteArray=packets["optics"].duplicate();optic.encode_u32(12,1 if sep else 0)
    var data: Dictionary={0:Model.patch_bytes(model),1:Model.light_bytes(model),2:packets["factors"],8:dims,9:Model.blocker_bytes(model),11:Model.triangle_bytes(model),12:Model.radius_bytes(model),13:Optics.bytes([]),17:packets["boxes"],19:optic,21:packets["outgoing"],22:packets["planes"],24:packets["owners"]}
    for pair in [[3,n*16*4],[4,16*4],[5,n*8*16],[6,n*8*16],[7,n*16],[18,n*8*32],[20,n*8*16],[23,n*8*16]]:
        var zero:=PackedByteArray();zero.resize(pair[1]);data[pair[0]]=zero
    if surface_bridge():
        var zero:=PackedByteArray();zero.resize(272+n*8*16);data[25]=zero
    var rids: Dictionary={};var uniforms: Array[RDUniform]=[]
    for binding in data:
        rids[binding]=rd.storage_buffer_create(data[binding].size(),data[binding]);uniforms.append(uniform(binding,rids[binding]))
    var format:=RDTextureFormat.new();format.width=n;format.height=1;format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
    var image_rid: RID=rd.texture_create(format,RDTextureView.new(),[]);uniforms.append(uniform(10,image_rid,true))
    var set_rid: RID=rd.uniform_set_create(uniforms,shader,0)
    check(set_rid.is_valid(),name+" real uniform set")
    if not set_rid.is_valid():return PackedFloat32Array()
    var channels: int=lights if sep else 1
    submit([[0,n*lights,0],[1,lights,0],[2,n*channels,0]],set_rid)
    if surface_bridge():submit([[6,n*lights,0]],set_rid)
    var previous: Array=totals(rd.buffer_get_data(rids[5]).to_float32_array(),n,channels)
    var generations: Array=[previous]
    for gen in range(model["bounces"]):
        submit([[5,n*channels,gen%2],[3,n*channels,gen%2]],set_rid)
        var current: Array=totals(rd.buffer_get_data(rids[6 if gen%2==0 else 5]).to_float32_array(),n,channels)
        for l in range(channels):
            for k in range(3):check(current[l][k]>=0 and is_finite(current[l][k]) and current[l][k]<=previous[l][k]+.00001,name+" passive source "+str(l))
        previous=current;generations.append(current)
    submit([[4,n,0]],set_rid)
    var output: PackedFloat32Array=rd.buffer_get_data(rids[7]).to_float32_array();var maximum: float=0.
    for i in range(n):
        for k in range(3):
            var actual: float=output[i*4+k];check(is_finite(actual) and actual>=0,name+" finite RGB")
            maximum=maxf(maximum,absf(actual-float(case["output"]["flux"][i][k])))
    check(maximum<.00003,name+" independent float64 error "+str(maximum))
    if surface_bridge():
        var packet: PackedByteArray=rd.buffer_get_data(rids[25])
        check(packet.decode_u32(0)==n and packet.decode_u32(4)==lights and packet.decode_u32(12)==1,name+" surface packet ABI")
        var direct: PackedFloat32Array=packet.slice(272).to_float32_array();var split_ok: bool=true
        var direct_initial: Array=generations[0];var packet_totals: Array=totals(direct,n,lights)
        for i in range(n):
            for k in range(3):
                var value: float=0.
                for l in range(lights):value+=direct[(l*n+i)*4+k]*float(model["patches"][i]["area"])
                split_ok=split_ok and value>=0. and value<=output[i*4+k]+.00003
        var packet_error: float=0.
        for k in range(3):
            var a: float=0.;var b: float=0.
            for l in range(lights):a+=packet_totals[l][k]
            for l in range(channels):b+=direct_initial[l][k]
            # packet_totals are irradiance; convert each receiver area above.
            var flux_sum: float=0.
            for i in range(n):
                for l in range(lights):flux_sum+=direct[(l*n+i)*4+k]*float(model["patches"][i]["area"])
            packet_error=maxf(packet_error,absf(flux_sum-b))
        check(split_ok and packet_error<.00003,name+" exact direct/indirect decomposition")
    report["cases"][name]={"max_error":maximum,"source_generations":generations};report["max_error"]=maxf(report["max_error"],maximum)
    rd.free_rid(set_rid);rd.free_rid(image_rid)
    for rid in rids.values():rd.free_rid(rid)
    return output
func run() -> void:
    var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/light-field-reference.json"))
    rd=RenderingServer.create_local_rendering_device()
    if rd==null:printerr("Actual Vulkan required");quit(1);return
    var spirv: RDShaderSPIRV=shader_resource().get_spirv();shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
    if not pipeline.is_valid():printerr(spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE));quit(1);return
    var outputs: Dictionary={}
    for name in fixture["cases"]:outputs[name]=execute(fixture["cases"][name],name)
    var superposition: float=0.;var legacy: float=0.
    for i in range(outputs["two_colored_lights"].size()):
        superposition=maxf(superposition,absf(outputs["two_colored_lights"][i]-outputs["left_only"][i]-outputs["right_only"][i]))
        legacy=maxf(legacy,absf(outputs["two_colored_lights"][i]-outputs["legacy_merged"][i]))
    check(superposition<.00001,"actual GPU source superposition");check(legacy>.0001,"merged-direction defect reproduced")
    report.merge({"checks":checks,"failed":failed,"device":rd.get_device_name(),"source_superposition_max_error":superposition,"legacy_merged_max_difference":legacy})
    var file:=FileAccess.open("res://light-field-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    rd.free_rid(pipeline);rd.free_rid(shader);rd.free()
    print("FIELD GPU ","FAIL" if failed else "PASS"," ",checks," cases ",fixture["cases"].size());quit(1 if failed else 0)
