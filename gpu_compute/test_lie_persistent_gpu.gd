extends SceneTree
const ShaderFile=preload("res://shaders/lie_persistent_visibility_test.glsl")
const Samples=preload("res://lie_shared_sample_buffers.gd")
var checks: int=0
var failed: bool=false
var rd: RenderingDevice
var shader: RID
var pipeline: RID
var rids: Dictionary={}
var set_rid: RID
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
    checks+=1
    if not value:failed=true;printerr("PERSISTENT GPU FAIL ",label)
func uniform(binding: int,rid: RID) -> RDUniform:
    var u:=RDUniform.new();u.binding=binding;u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.add_id(rid);return u
func solve() -> Dictionary:
    rd.buffer_update(rids[8],0,8,PackedInt32Array([0,-2147483648]).to_byte_array())
    var list: int=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set_rid,0)
    for stage in [13,12,11]:rd.compute_list_set_push_constant(list,PackedInt32Array([stage]).to_byte_array(),4);rd.compute_list_dispatch(list,1,1,1);rd.compute_list_add_barrier(list)
    rd.compute_list_end();rd.submit();rd.sync()
    var packed: PackedByteArray=rd.buffer_get_data(rids[8]);var result: Array=[]
    for l in range(8):
        var mask: int=127 if l==7 else 255;result.append(float((packed.decode_u32(0 if l<4 else 4)>>(l%4*8))&mask)/mask)
    var stats: PackedInt32Array=rd.buffer_get_data(rids[31]).to_int32_array()
    return {"visibility":result,"hits":Array(stats.slice(4,12)),"queries":Array(stats.slice(12,20)),"skips":Array(stats.slice(20,28)),"dirty":rd.buffer_get_data(rids[30],0,4).decode_u32(0)}
func all_equal(values: Array,value: int) -> bool:
    for v in values:
        if v!=value:return false
    return true
func matches(values: Array,expected: float,changed: float) -> bool:
    for l in range(8):
        if absf(values[l]-(changed if l==3 else expected))>1./127.+.00001:return false
    return true
func run() -> void:
    rd=RenderingServer.create_local_rendering_device()
    if rd==null:printerr("Actual Vulkan required");quit(1);return
    shader=rd.shader_create_from_spirv(ShaderFile.get_spirv());pipeline=rd.compute_pipeline_create(shader)
    if not pipeline.is_valid():printerr(ShaderFile.get_spirv().get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE));quit(1);return
    var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/persistent-visibility-reference.json"));var results: Dictionary={}
    for case in fixture["cases"]:
        var control:=PackedInt32Array([1,1,1,0]).to_byte_array();control.resize(128)
        var cache:=PackedByteArray();cache.resize(268)
        var options: PackedByteArray=PackedInt32Array([1,1,12,1]).to_byte_array();options.append_array(PackedFloat32Array([.025,.0003,0.,0.]).to_byte_array())
        var lights: PackedByteArray=PackedInt32Array([0,8,0,0]).to_byte_array()
        for l in range(8):lights.append_array(PackedFloat32Array([case["light"][0],case["light"][1],case["light"][2],10.,1.,1.,1.,.0001]).to_byte_array())
        var data: Dictionary={0:str(case["bank_hex"]).hex_decode(),1:str(case["nodes_hex"]).hex_decode(),2:str(case["leaves_hex"]).hex_decode(),3:str(case["scene_hex"]).hex_decode(),4:PackedFloat32Array(case["projection"]).to_byte_array(),5:options,6:PackedInt32Array([1,1,0,0]).to_byte_array(),7:lights,8:PackedInt32Array([0,-2147483648]).to_byte_array(),29:PackedInt32Array([0,0]).to_byte_array(),30:cache,31:control}
        rids={};var uniforms: Array[RDUniform]=[]
        for binding in data:rids[binding]=rd.storage_buffer_create(data[binding].size(),data[binding]);uniforms.append(uniform(binding,rids[binding]))
        set_rid=rd.uniform_set_create(uniforms,shader,0);check(set_rid.is_valid(),case["name"]+" actual kernel bindings")
        var cold: Dictionary=solve();check(all_equal(cold["queries"],1) and all_equal(cold["hits"],0),"cold queries all eight source slots")
        check(matches(cold["visibility"],case["expected"][0],case["expected"][0]),case["name"]+" float64 and UNORM agreement")
        var warm: Dictionary=solve();check(warm["visibility"]==cold["visibility"] and all_equal(warm["queries"],0) and all_equal(warm["hits"],1),"zero and fractional visibility are valid persistent hits")
        for l in range(8):
            for k in range(3):lights.encode_float(16+l*32+16+k*4,.31+float(k)*.2)
        rd.buffer_update(rids[7],0,lights.size(),lights);var power: Dictionary=solve()
        check(power["visibility"]==cold["visibility"] and power["dirty"]==0 and all_equal(power["queries"],0),"radiometry preserves all geometric visibility")
        for k in range(3):lights.encode_float(16+3*32+k*4,case["moved_light"][k])
        rd.buffer_update(rids[7],0,lights.size(),lights);var moved: Dictionary=solve()
        check(moved["dirty"]==8 and moved["queries"][3]==1 and moved["hits"][3]==0,"only the moved source invalidates")
        var other: bool=true
        for l in range(8):
            if l!=3:other=other and moved["hits"][l]==1 and moved["queries"][l]==0
        check(other and matches(moved["visibility"],case["expected"][0],case["moved_expected"]),"other sources reuse exact results; moved ray matches oracle")
        rd.buffer_update(rids[30],4,4,PackedInt32Array([0]).to_byte_array());var rebuilt: Dictionary=solve()
        check(rebuilt["visibility"]==moved["visibility"] and all_equal(rebuilt["queries"],1),"forced cold matches cached invalidation")
        rd.buffer_update(rids[30],4,4,PackedInt32Array([0]).to_byte_array())
        for k in range(3):lights.encode_float(16+7*32+16+k*4,0.)
        rd.buffer_update(rids[7],0,lights.size(),lights);var off: Dictionary=solve()
        check(off["queries"][7]==0 and off["skips"][7]==1,"zero power does not certify untested visibility")
        for k in range(3):lights.encode_float(16+7*32+16+k*4,1.)
        rd.buffer_update(rids[7],0,lights.size(),lights);var on: Dictionary=solve()
        check(on["queries"][7]==1 and on["visibility"]==rebuilt["visibility"],"reenabling eighth source queries missing result and retains seven-bit precision")
        options.encode_float(16,.02);options.encode_float(20,.00033);rd.buffer_update(rids[5],0,32,options);var metric: Dictionary=solve()
        check(all_equal(metric["queries"],1) and matches(metric["visibility"],case["metric_expected"],case["metric_moved_expected"]),"reach and bias changes invalidate all channels against oracle")
        rd.buffer_update(rids[31],0,4,PackedInt32Array([0]).to_byte_array());var fallback: Dictionary=solve()
        check(fallback["visibility"]==metric["visibility"] and all_equal(fallback["queries"],1),"uncached exact comparison path")
        results[case["name"]]={"reference":case["expected"][0],"cold":cold,"warm":warm,"moved":moved,"metric":metric}
        rd.free_rid(set_rid)
        for rid in rids.values():rd.free_rid(rid)
    var bytes:=PackedByteArray();bytes.resize(160);var hashing:=HashingContext.new();hashing.start(HashingContext.HASH_SHA256);hashing.update(bytes);var digest: String=hashing.finish().hex_encode()
    var first: Dictionary=Samples.acquire(rd,bytes,digest,80);var second: Dictionary=Samples.acquire(rd,bytes,digest,80)
    check(first["generation"]==second["generation"] and first["rid"]==second["rid"],"two handles share a resident bank generation")
    check(Samples.resolve(rd,first,1)["byte_offset"]==80 and Samples.resolve(rd,first,2).is_empty(),"direct bank address and range guard")
    Samples.release(rd,first["key"]);check(not Samples.resolve(rd,first,0).is_empty(),"one release preserves remaining bank owner")
    Samples.release(rd,second["key"]);check(Samples.resolve(rd,first,0).is_empty(),"evicted address is rejected")
    var replacement: Dictionary=Samples.acquire(rd,bytes,digest,80);check(replacement["generation"]!=first["generation"] and Samples.resolve(rd,first,0).is_empty(),"reloaded bank cannot revive a stale handle")
    check(not Samples.release_handle(rd,first) and not Samples.resolve(rd,replacement,0).is_empty(),"stale release cannot free the replacement bank");Samples.release_handle(rd,replacement)
    var file:=FileAccess.open("res://persistent-visibility-native.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"cases":results,"device":rd.get_device_name(),"physical_android_tested":false},"  ",true,true));file.close()
    rd.free_rid(pipeline);rd.free_rid(shader);rd.free();print("PERSISTENT GPU ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
