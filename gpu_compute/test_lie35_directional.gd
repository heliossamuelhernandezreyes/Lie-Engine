extends SceneTree
## Real compute pipeline proof against independent Python float64 oracle.
## This lab intentionally does not alter LIE11/WALL04 or register visible meshes.
const ShaderFile=preload("res://shaders/lie35_directional.glsl")
var checks: int=0
var errors: int=0
var rd: RenderingDevice
var shader: RID
var pipeline: RID

func _initialize() -> void:
    call_deferred("_run")

func check(ok: bool, message: String) -> void:
    checks+=1
    if not ok:
        errors+=1
        printerr("LIE35 FAIL: ",message)

func floats(numbers: Array) -> PackedFloat32Array:
    var packet:=PackedFloat32Array()
    for value in numbers:packet.append(float(value))
    return packet

func input_sources(values: Array) -> PackedByteArray:
    var data:=PackedFloat32Array()
    for source in values:
        for part in [
            [source["position"][0],source["position"][1],source["position"][2],source["radius"]],
            [source["normal"][0],source["normal"][1],source["normal"][2],source["roughness"]],
            [source["incident"][0],source["incident"][1],source["incident"][2],source["metallic"]],
            [source["albedo"][0],source["albedo"][1],source["albedo"][2],source["transmission"]],
            [source["sigma"][0],source["sigma"][1],source["sigma"][2],source["thickness"]],
            [source["power"][0],source["power"][1],source["power"][2],source["ior"]]
        ]:
            data.append_array(floats(part))
    return data.to_byte_array()

func input_receivers(values: Array) -> PackedByteArray:
    var data:=PackedFloat32Array()
    for target in values:
        data.append_array(floats([
            target["position"][0],target["position"][1],target["position"][2],target["area"],
            target["normal"][0],target["normal"][1],target["normal"][2],
            1.0 if target["visible"] else 0.0
        ]))
    return data.to_byte_array()

func uniform(index: int, rid: RID) -> RDUniform:
    var item:=RDUniform.new()
    item.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    item.binding=index
    item.add_id(rid)
    return item

func dispatch(commands: int, phase: int, sources: int, receivers: int) -> void:
    rd.compute_list_set_push_constant(commands,PackedInt32Array([phase,sources,receivers,0]).to_byte_array(),16)
    var threads: int=receivers if phase==2 else sources
    rd.compute_list_dispatch(commands,int(ceil(float(threads)/64.0)),1,1)

func case_gpu(test: Dictionary) -> PackedFloat32Array:
    var ns: int=test["emitters"].size()
    var nr: int=test["receivers"].size()
    var source_bytes:=input_sources(test["emitters"])
    var target_bytes:=input_receivers(test["receivers"])
    var source:=rd.storage_buffer_create(source_bytes.size(),source_bytes)
    var target:=rd.storage_buffer_create(target_bytes.size(),target_bytes)
    var weight:=rd.storage_buffer_create(ns*nr*16)
    var norm:=rd.storage_buffer_create(ns*16)
    var output:=rd.storage_buffer_create(nr*16)
    var rids: Array[RID]=[source,target,weight,norm,output]
    for rid in rids:
        if not rid.is_valid():
            check(false,"Buffer allocation failed")
            return PackedFloat32Array()
    var bindings: Array[RDUniform]=[]
    for i in range(rids.size()):bindings.append(uniform(i,rids[i]))
    var set_rid:=rd.uniform_set_create(bindings,shader,0)
    if not set_rid.is_valid():
        check(false,"Uniform set creation failed")
        return PackedFloat32Array()
    var commands:=rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(commands,pipeline)
    rd.compute_list_bind_uniform_set(commands,set_rid,0)
    for phase in range(3):
        dispatch(commands,phase,ns,nr)
        if phase!=2:rd.compute_list_add_barrier(commands)
    rd.compute_list_end()
    rd.submit()
    rd.sync()
    var pixels:=rd.buffer_get_data(output).to_float32_array()
    rd.free_rid(set_rid)
    for rid in rids:rd.free_rid(rid)
    return pixels

func _run() -> void:
    var fixture: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/lie35-directional-reference.json"))
    if not fixture is Dictionary or fixture.get("schema")!="lie35-angular/1":
        check(false,"Missing generated independent LIE35 fixture")
        quit(1)
        return
    rd=RenderingServer.create_local_rendering_device()
    if rd==null:
        check(false,"Real Vulkan RenderingDevice required")
        quit(1)
        return
    var spirv: RDShaderSPIRV=ShaderFile.get_spirv()
    if spirv==null:
        check(false,"LIE35 GLSL shader not imported")
        quit(1)
        return
    shader=rd.shader_create_from_spirv(spirv)
    if not shader.is_valid():
        check(false,"Directional compute shader compilation failed")
        quit(1)
        return
    pipeline=rd.compute_pipeline_create(shader)
    if not pipeline.is_valid():
        check(false,"Directional compute pipeline failed")
        quit(1)
        return
    var report: Dictionary={"device":rd.get_device_name(),"max_error":0.0,"cases":{},"physical_gpu_measured":false}
    for name in fixture["cases"]:
        var data: Dictionary=fixture["cases"][name]
        var computed: PackedFloat32Array=case_gpu(data)
        if computed.size()!=data["receivers"].size()*4:
            check(false,"Wrong GPU output dimensions "+name)
            break
        var maximum: float=0.0
        for i in range(data["receivers"].size()):
            for c in range(3):
                var actual: float=computed[i*4+c]
                var expected: float=data["output"][i][c]
                check(is_finite(actual) and actual>=0,"Finite nonnegative GPU RGB "+name)
                var error: float=absf(actual-expected)
                maximum=maxf(maximum,error)
        check(maximum<0.00005,"Float64 reference agreement "+name+": "+str(maximum))
        for c in range(3):
            var gained: float=0.0
            for i in range(data["receivers"].size()):gained+=computed[i*4+c]
            check(gained<=float(data["incoming_total"][c])+0.00005,"Conservation channel "+str(c)+" "+name)
        report["cases"][name]={"max_error":maximum}
        report["max_error"]=maxf(float(report["max_error"]),maximum)
    rd.free_rid(pipeline)
    rd.free_rid(shader)
    print("LIE35-DIRECTIONAL-NATIVE ",JSON.stringify(report))
    print("LIE35-DIRECTIONAL-CHECKS ",checks," errors ",errors)
    quit(1 if errors>0 else 0)
