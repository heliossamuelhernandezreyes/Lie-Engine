extends SceneTree
const Kernels=preload("res://lie_screen_tile_kernels.gd")
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("TILE PREFIX FAIL ",label)
func uniform(binding: int,rid: RID) -> RDUniform:
    var u:=RDUniform.new();u.binding=binding;u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.add_id(rid);return u
func run() -> void:
    var rd: RenderingDevice=RenderingServer.create_local_rendering_device()
    if rd==null:printerr("Actual Vulkan required");quit(1);return
    var programs: Dictionary={};var cases: Array=[]
    for key in ["scan","groups"]:
        var shader: RID=rd.shader_create_from_spirv(Kernels.SHADERS[key].get_spirv());programs[key]={"shader":shader,"pipeline":rd.compute_pipeline_create(shader)}
    for size in [1,8,63,65,1081,1440]:
        var columns: int=ceili(float(size)/8.);var tiles: int=columns*columns;var blocks: int=ceili(float(tiles)/64.)
        var params:=PackedByteArray();params.resize(256);params.encode_u32(88,size);params.encode_u32(92,size)
        var table:=PackedByteArray();table.resize(tiles*16);var groups:=PackedByteArray();groups.resize((blocks+1)*4)
        var expected: Array=[];var total: int=0
        for i in range(tiles):
            var count: int=1301 if i%137==0 else 0 if i%3==0 else i%31
            table.encode_u32(i*16,count);expected.append(total);total+=count
        var raw: Dictionary={6:params,41:table,43:groups};var rids: Dictionary={};var sets: Dictionary={}
        for binding in raw:rids[binding]=rd.storage_buffer_create(raw[binding].size(),raw[binding])
        for key in programs:
            var uniforms: Array[RDUniform]=[]
            for binding in Kernels.BINDINGS[key]:uniforms.append(uniform(binding,rids[binding]))
            sets[key]=rd.uniform_set_create(uniforms,programs[key]["shader"],0)
        var list: int=rd.compute_list_begin()
        for key in ["scan","groups"]:
            rd.compute_list_bind_compute_pipeline(list,programs[key]["pipeline"]);rd.compute_list_bind_uniform_set(list,sets[key],0);rd.compute_list_set_push_constant(list,PackedInt32Array([0,2,0,0]).to_byte_array(),16);rd.compute_list_dispatch(list,blocks if key=="scan" else 1,1,1);rd.compute_list_add_barrier(list)
        rd.compute_list_end();rd.submit();rd.sync()
        var actual: PackedByteArray=rd.buffer_get_data(rids[41]);var sums: PackedByteArray=rd.buffer_get_data(rids[43]);var exact: bool=true
        for i in range(tiles):exact=exact and int(actual.decode_u32(i*16+8))+int(sums.decode_u32((i/64)*4))==expected[i]
        check(exact,"every exclusive offset at size "+str(size));check(sums.decode_u32(blocks*4)==total,"exact total including >256 references in a tile")
        cases.append({"size":size,"tiles":tiles,"blocks":blocks,"references":total})
        for rid in sets.values():rd.free_rid(rid)
        for rid in rids.values():rd.free_rid(rid)
    for entry in programs.values():rd.free_rid(entry["pipeline"]);rd.free_rid(entry["shader"])
    var file:=FileAccess.open("res://screen-prefix-native.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"cases":cases,"device":rd.get_device_name()},"  "));file.close()
    rd.free();print("TILE PREFIX ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
