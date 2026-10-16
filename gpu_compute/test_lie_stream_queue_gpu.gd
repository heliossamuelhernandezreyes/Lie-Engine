extends SceneTree
const Shader=preload("res://shaders/lie_wall19_compact.glsl")
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("STREAM QUEUE FAIL ",label)
func uniform(binding: int,rid: RID) -> RDUniform:
    var u:=RDUniform.new();u.binding=binding;u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.add_id(rid);return u
func run() -> void:
    var rd: RenderingDevice=RenderingServer.create_local_rendering_device()
    if rd==null:printerr("Actual Vulkan required");quit(1);return
    var shader: RID=rd.shader_create_from_spirv(Shader.get_spirv());var pipeline: RID=rd.compute_pipeline_create(shader);var evidence: Array=[]
    for count in [1,63,64,65,130,535670]:
        for pattern in range(3):
            var params:=PackedByteArray();params.resize(256);params.encode_u32(80,count)
            var source:=PackedInt32Array();var order:=PackedInt32Array();order.resize(19);var expected: Array=[]
            for i in range(count):source.append(1 if pattern==2 or (pattern==1 and i%3==0) else 0);source.append(0)
            for i in range(count):
                var id: int=count-i-1;order.append(id)
                if source[id*2]!=0:expected.append(id)
            var header:=PackedInt32Array([0,1,1,0]);header.resize(4+count)
            var raw: Dictionary={6:params,28:source.to_byte_array(),35:header.to_byte_array(),37:order.to_byte_array()};var rids: Dictionary={};var uniforms: Array[RDUniform]=[]
            for binding in raw:rids[binding]=rd.storage_buffer_create(raw[binding].size(),raw[binding]);uniforms.append(uniform(binding,rids[binding]))
            var set_rid: RID=rd.uniform_set_create(uniforms,shader,0);var list: int=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set_rid,0);rd.compute_list_set_push_constant(list,PackedInt32Array([0,2,0,19]).to_byte_array(),16);rd.compute_list_dispatch(list,ceili(float(count)/64.),1,1);rd.compute_list_end();rd.submit();rd.sync()
            var actual: PackedInt32Array=rd.buffer_get_data(rids[35]).to_int32_array();var ids: Array=Array(actual.slice(4,4+actual[3]));var sorted: Array=ids.duplicate();sorted.sort();var expected_sorted: Array=expected.duplicate();expected_sorted.sort()
            check(actual[3]==expected.size() and sorted==expected_sorted,"exact unique winners "+str(count)+" "+str(pattern));check(actual[0]==ceili(float(expected.size())/64.),"indirect count")
            var ordered: bool=true
            if count<1000:
                for start in range(0,count,64):
                    var block: Array=[]
                    for at in range(start,mini(start+64,count)):
                        var id: int=order[19+at]
                        if source[id*2]!=0:block.append(id)
                    if not block.is_empty():
                        var at: int=ids.find(block[0]);ordered=ordered and ids.slice(at,at+block.size())==block
            check(ordered,"spatial block lane order");evidence.append({"count":count,"pattern":pattern,"selected":actual[3]})
            rd.free_rid(set_rid)
            for rid in rids.values():rd.free_rid(rid)
    var file:=FileAccess.open("res://stream-queue-native.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"cases":evidence,"device":rd.get_device_name()},"  "));file.close()
    rd.free_rid(pipeline);rd.free_rid(shader);rd.free();print("STREAM QUEUE ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
