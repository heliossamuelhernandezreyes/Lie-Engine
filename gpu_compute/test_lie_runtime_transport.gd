extends SceneTree
## Real native Vulkan: unchanged dense equations vs CSR, oracle and cache.
const Model=preload("res://lie11_model.gd")
const Dense=preload("res://lie11_light_effect.gd")
const Sparse=preload("res://lie11_sparse_light_effect.gd")
const Wall=preload("res://lie_wall04_transport.gd")
var checks: int=0
var failed: bool=false
var report: Dictionary={"cases":{},"physical_gpu_measured":false}
var viewports: Array[SubViewport]=[]

func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
    checks+=1
    if not value:failed=true;printerr("RUNTIME TRANSPORT FAIL ",message)
func settle(count: int=6) -> void:
    for i in range(count):await process_frame

func attach(effect: CompositorEffect) -> SubViewport:
    var viewport:=SubViewport.new();viewport.size=Vector2i(128,128)
    viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
    get_root().add_child(viewport);viewports.append(viewport)
    var world:=WorldEnvironment.new();world.environment=Environment.new()
    world.environment.background_mode=Environment.BG_COLOR
    var compositor:=Compositor.new();compositor.compositor_effects=[effect];world.compositor=compositor
    viewport.add_child(world)
    var camera:=Camera3D.new();viewport.add_child(camera);camera.current=true
    camera.position=Vector3(0,2,4);camera.look_at(Vector3(0,.5,0),Vector3.UP)
    return viewport

func capture(effect: CompositorEffect) -> Dictionary:
    effect.call("request_readback")
    for i in range(120):
        await process_frame
        var result: Dictionary=effect.call("readback")
        if not result.is_empty():return result
    check(false,"Actual GPU readback timed out");return {}

func difference(a: PackedFloat32Array,b: PackedFloat32Array) -> float:
    if a.size()!=b.size():return INF
    var maximum: float=0
    for i in range(a.size()):maximum=maxf(maximum,absf(a[i]-b[i]))
    return maximum

func run() -> void:
    var oracle: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/lie-runtime-reference.json"))
    if not oracle is Dictionary:check(false,"Generate float64 runtime reference");quit(1);return
    var source: Dictionary=Model.load_room()
    var dense:=Dense.new();var sparse:=Sparse.new()
    dense.profile_transport=true
    check(dense.configure(source) and sparse.configure(source),"Initial full real graph accepted")
    attach(dense);attach(sparse);await settle(12)
    if not dense.gpu_ready or not sparse.gpu_ready:
        check(false,"Real Vulkan required: "+dense.failure+" / "+sparse.failure);quit(1);return
    for name in ["direct","bounce","absorbing","blocked","moved","cool"]:
        var model: Dictionary=Model.scenario(source,name)
        check(dense.configure(model) and sparse.configure(model),"Scenario accepted "+name)
        await settle()
        var a: Dictionary=await capture(dense);var b: Dictionary=await capture(sparse)
        if a.is_empty() or b.is_empty():quit(1);return
        var error: float=difference(a["irradiance"],b["irradiance"])
        check(error<=.00002,"CSR equals dense irradiance "+name)
        check(difference(a["flux"],b["flux"])<=.00002,"CSR equals dense power "+name)
        report["cases"][name]={"dense_sparse_max_error":error}
    for name in oracle["scenarios"]:
        var entry: Dictionary=oracle["scenarios"][name];var model: Dictionary=entry["model"]
        check(dense.configure(model) and sparse.configure(model),"Opt-in policy "+name)
        await settle();var data: Dictionary=await capture(sparse)
        if data.is_empty():quit(1);return
        var expected: Array=entry["reference"]["irradiance"]
        var max_error: float=0;var total_error: float=0;var denominator: float=0
        for p in range(expected.size()):
            for c in range(3):
                var value: float=data["irradiance"][p*4+c];var target: float=expected[p][c]
                check(is_finite(value) and value>=0,"Finite physical irradiance")
                max_error=maxf(max_error,absf(value-target));total_error+=absf(value-target);denominator+=absf(target)
        var relative: float=total_error/maxf(denominator,.00000001)
        check(max_error<.003 and relative<.0001,"Independent float64 light oracle "+name)
        var baseline: Dictionary=await capture(dense)
        check(difference(data["irradiance"],baseline["irradiance"])<.00002,"Both GPU policies agree "+name)
        report["cases"][name]={"oracle_max_error":max_error,"oracle_relative_l1":relative}
    check(dense.configure(source) and sparse.configure(source),"Reset base")
    await settle();var before: int=sparse.frame_count;var dense_before: int=dense.frame_count
    await settle(12)
    check(sparse.frame_count==before,"Unchanged scene resolves no more lighting")
    check(dense.frame_count>dense_before,"Dense legacy continuously solves reference")
    var builds: int=sparse.factor_builds
    var edited: Dictionary=source.duplicate(true);edited["lights"][0]["power_rgb"]=[4,7,12]
    check(sparse.configure(edited),"Light edit")
    edited["materials"]["red"]["absorption_code"]=950
    check(sparse.configure(edited),"Coalesced material edit")
    check(sparse.factor_builds==builds,"Lights/materials reuse exact geometry factors")
    check(dense.configure(edited),"Reference final coalesced input")
    await settle();var final_a: Dictionary=await capture(dense);var final_b: Dictionary=await capture(sparse)
    check(difference(final_a["irradiance"],final_b["irradiance"])<.00002,"Final coalesced packet, never stale geometry")
    var bad: Dictionary=edited.duplicate(true);bad["secondary_radii"]={"mode":"irradiance","radius_max":6,"radius_decay":.8,"irradiance_cutoff":0}
    check(not sparse.configure(bad),"Invalid physical policy rejected")
    # A fixed node count with new facing normals grows CSR; output RID is stable.
    var tiny: Dictionary=source.duplicate(true);tiny["patches"]=[]
    for position in [[1,0,0],[-1,0,0],[0,0,1],[0,0,-1]]:
        tiny["patches"].append({"position":position,"normal":[0,1,0],"area":.1,"gray_mean":.7,"material":"red"})
    var growing:=Sparse.new();check(growing.configure(tiny),"Small empty graph accepted");attach(growing);await settle()
    var old_rid: RID=growing.output_rid;var old_bytes: int=growing.transport_metrics()["factor_buffer_capacity_bytes"]
    for patch in tiny["patches"]:
        var direction: Vector3=-Model.vector(patch["position"]).normalized();patch["normal"]=[direction.x,direction.y,direction.z]
    check(growing.configure(tiny),"Geometry invalidates graph")
    await settle();check(growing.gpu_ready and growing.output_rid==old_rid,"Graph growth preserves published irradiance")
    check(growing.transport_metrics()["factor_buffer_capacity_bytes"]>old_bytes,"Actual graph buffer resized")
    # WALL04 uses the exact SHA-locked photographed/source bank's light nodes.
    var wall_model: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://captures/liewall04/light-model.json"))
    var wall_dense:=Wall.new(false);var wall_sparse:=Wall.new(true)
    check(wall_dense.assign_shadow_boxes(wall_model["direct_shadow_boxes"]) and wall_sparse.assign_shadow_boxes(wall_model["direct_shadow_boxes"]),"96 real noncolliding shadow proxies")
    check(wall_dense.configure(wall_model) and wall_sparse.configure(wall_model),"Source-locked 872-patch transport")
    attach(wall_dense);attach(wall_sparse);await settle()
    for shadow_state in [true,false,true]:
        wall_dense.set_direct_shadow_enabled(shadow_state);wall_sparse.set_direct_shadow_enabled(shadow_state)
        await settle();var wa: Dictionary=await capture(wall_dense);var wb: Dictionary=await capture(wall_sparse)
        if wa.is_empty() or wb.is_empty():quit(1);return
        check(difference(wa["irradiance"],wb["irradiance"])<.00002,"WALL04 dense/CSR shadow toggle "+str(shadow_state))
        report["cases"]["wall_shadow_"+str(shadow_state)]={"max_error":difference(wa["irradiance"],wb["irradiance"])}
    var wall_before: int=wall_sparse.frame_count;await settle(8)
    check(wall_sparse.frame_count==wall_before,"Photographed wall light cache idles")
    report.merge({"checks":checks,"failed":failed,"device":final_b["device"],"sparse_metrics":sparse.transport_metrics(),
        "wall_dense_metrics":wall_dense.transport_metrics(),"wall_sparse_metrics":wall_sparse.transport_metrics(),
        "factor_builds":sparse.factor_builds,"factor_reuses":sparse.factor_reuses})
    var out:=FileAccess.open("res://lie-runtime-transport.json",FileAccess.WRITE);out.store_string(JSON.stringify(report,"  ",true,true));out.close()
    for effect in [dense,sparse,growing,wall_dense,wall_sparse]:effect.shutdown()
    await settle();for viewport in viewports:viewport.queue_free()
    print("LIE RUNTIME TRANSPORT ","FAIL" if failed else "PASS"," ",checks," real Vulkan checks")
    quit(1 if failed else 0)
