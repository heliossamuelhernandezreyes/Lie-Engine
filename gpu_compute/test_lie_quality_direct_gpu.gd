extends SceneTree
## Executes the exact final shader on a one-pixel opening/occluder fixture.
const ShaderFile=preload("res://shaders/lie_quality_direct_light.glsl")
const Quality=preload("res://lie_field_quality_model.gd")
var rd: RenderingDevice
var shader: RID
var pipeline: RID
var sampler: RID
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("QUALITY DIRECT FAIL ",label)
func uniform(binding: int,rid: RID,kind: int) -> RDUniform:
    var u:=RDUniform.new();u.binding=binding;u.uniform_type=kind
    if kind==RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE:u.add_id(sampler)
    u.add_id(rid);return u
func texture(values: Array,layers: int=1) -> RID:
    var f:=RDTextureFormat.new();f.width=1;f.height=1;f.array_layers=layers
    f.texture_type=RenderingDevice.TEXTURE_TYPE_2D_ARRAY if layers>1 else RenderingDevice.TEXTURE_TYPE_2D
    f.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    f.usage_bits=RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
    var rows: Array[PackedByteArray]=[]
    for i in range(layers):rows.append(PackedFloat32Array(values).to_byte_array())
    return rd.texture_create(f,RDTextureView.new(),rows)
func execute(shadow: float,dynamic: bool,fine: bool=true) -> PackedFloat32Array:
    var rids: Array[RID]=[];var uniforms: Array[RDUniform]=[]
    for pair in [[0,[0.,0.,0.,1.]],[1,[0.,0.,1.,.8]],[2,[1.,1.,1.,1.]],[3,[shadow,0.,0.,0.]]]:
        var rid: RID=texture(pair[1],6 if pair[0]==3 else 1);rids.append(rid)
        uniforms.append(uniform(pair[0],rid,RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE))
    var output: RID=texture([0.,0.,0.,0.]);rids.append(output);uniforms.append(uniform(4,output,RenderingDevice.UNIFORM_TYPE_IMAGE))
    var field: RID=texture([0.,0.,0.,0.]);rids.append(field);uniforms.append(uniform(5,field,RenderingDevice.UNIFORM_TYPE_IMAGE))
    var lights:=PackedInt32Array([1,1,16,1]).to_byte_array();lights.resize(16+17*16)
    for pair in [[0,0.],[1,0.],[2,1.],[3,10.],[4,4.*PI],[5,4.*PI],[6,4.*PI],[7,.0025]]:lights.encode_float(16+int(pair[0])*4,float(pair[1]))
    var views:=PackedFloat32Array()
    for i in range(7):views.append_array(PackedFloat32Array([0,0,3 if i==0 else 1,0,1,0,0,0,0,1,0,0,0,0,-1,0,.1,10,0,0]))
    var opts:=PackedInt32Array([1,0,0,1 if fine else 0]).to_byte_array();opts.append_array(PackedFloat32Array([0,0,0,0]).to_byte_array())
    var q: Dictionary={}
    if dynamic:q={"dynamic_occluders":[[[-.1,-.1,.4],[.1,.1,.6]]],"visibility_revision":1}
    var buffers: Dictionary={6:PackedFloat32Array([0,0,0,.1,0,0,1,1,1,1,1,0]).to_byte_array(),7:lights,
        8:PackedInt32Array([0,0,0,0]).to_byte_array(),9:views.to_byte_array(),10:PackedFloat32Array([0,0,0,0,1,1,1,0]).to_byte_array(),
        11:PackedFloat32Array([0,0,0,0]).to_byte_array(),12:opts,13:Quality.packet([.1],q)}
    for binding in buffers:
        var rid: RID=rd.storage_buffer_create(buffers[binding].size(),buffers[binding]);rids.append(rid)
        uniforms.append(uniform(binding,rid,RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER))
    var set_rid: RID=rd.uniform_set_create(uniforms,shader,0);check(set_rid.is_valid(),"exact fine-light uniform ABI")
    if not set_rid.is_valid():return PackedFloat32Array()
    var list: int=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set_rid,0)
    rd.compute_list_set_push_constant(list,PackedInt32Array([1,0,0,0]).to_byte_array(),16);rd.compute_list_dispatch(list,1,1,1)
    rd.compute_list_end();rd.submit();rd.sync()
    var value: PackedFloat32Array=rd.texture_get_data(output,0).to_float32_array()
    rd.free_rid(set_rid)
    for rid in rids:rd.free_rid(rid)
    return value
func run() -> void:
    rd=RenderingServer.create_local_rendering_device()
    if rd==null:printerr("Actual Vulkan required");quit(1);return
    var spirv: RDShaderSPIRV=ShaderFile.get_spirv();shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
    if not pipeline.is_valid():printerr(spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE));quit(1);return
    sampler=rd.sampler_create(RDSamplerState.new())
    var old: PackedFloat32Array=execute(1.,false,false)
    var open: PackedFloat32Array=execute(1.,false)
    var closed: PackedFloat32Array=execute(0.,false)
    var blocked: PackedFloat32Array=execute(1.,true)
    check(old.size()==4 and old[0]==0.,"coarse zero gate reproduces lost opening")
    check(open.size()==4 and open[0]>.1,"fine visibility recovers the opening")
    check(closed.size()==4 and closed[0]==0.,"closed fine shadow stays opaque")
    check(blocked.size()==4 and blocked[0]==0.,"shared dynamic blocker masks final pixel")
    var f:=FileAccess.open("res://quality-direct-native.json",FileAccess.WRITE)
    f.store_string(JSON.stringify({"checks":checks,"failed":failed,"device":rd.get_device_name(),"old_gate":Array(old),"open":Array(open),"closed":Array(closed),"dynamic":Array(blocked)},"  ",true,true));f.close()
    rd.free_rid(sampler);rd.free_rid(pipeline);rd.free_rid(shader);rd.free()
    print("QUALITY DIRECT ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
