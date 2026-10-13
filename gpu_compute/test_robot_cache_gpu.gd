extends SceneTree
## Compare real GPU color/depth against the unchanged pre-cache shader.
const Lab=preload("res://lie_robot_world_lab.gd")
const WorldEffect=preload("res://lie_robot_world_effect.gd")
const ReferenceShader=preload("res://tests/fixtures/lie_robot_reference.glsl")
class ReferenceEffect extends WorldEffect:
    func shader_resource() -> RDShaderFile:return ReferenceShader
    func initialize_extra_buffers() -> void:_buffer(14,MAX_CURVES*CURVE_BYTES)
    func dispatch_reconstruction(_next: Dictionary,work: int) -> void:
        var list: int=_rd.compute_list_begin();_rd.compute_list_bind_compute_pipeline(list,_pipeline);_rd.compute_list_bind_uniform_set(list,_set,0)
        for stage in [1,2,3,4,6,7]:
            var count: int=work if stage in [2,3] else maxi(render_size*render_size,512*512) if stage==1 else output_size*output_size if stage==7 else render_size*render_size
            _rd.compute_list_set_push_constant(list,PackedInt32Array([stage,2,0,0]).to_byte_array(),16)
            _rd.compute_list_dispatch(list,int(ceil(float(count)/64)),1,1);_rd.compute_list_add_barrier(list)
        _rd.compute_list_end()
class ReferenceLab extends Lab:
    func create_effect(size: int) -> CompositorEffect:return ReferenceEffect.new(size)
var lab: Node3D
var checks: int=0
var failed: bool=false
var results: Array=[]
var cases: Array=[
    {"name":"initial","values":{}},
    {"name":"camera","values":{"camera_yaw":20}},
    {"name":"grip","values":{"grip":.8}},
    {"name":"power","values":{"light_power":1.5}},
    {"name":"light_direction","values":{"light_azimuth":30}},
    {"name":"roof","values":{"roof":true}},
    {"name":"cables_off","values":{"cables":false}},
    {"name":"cables_on","values":{"cables":true}},
    {"name":"shadows_off","values":{"shadows":false}},
    {"name":"pose_while_shadows_off","values":{"grip":.2}},
    {"name":"shadows_on","values":{"shadows":true}},
    {"name":"unlit","values":{"unlit":true}},
    {"name":"camera_inside","values":{"camera_distance":1.5,"camera_yaw":-80,"camera_elevation":40}},
    {"name":"roof_off","values":{"roof":false,"unlit":false}},
    {"name":"walk","values":{"move":[0,1]},"ticks":8},
    {"name":"exposure","values":{"exposure":1.2}},
]
func _initialize() -> void:call_deferred("run")
func expect(value: bool,label: String) -> void:
    checks+=1
    if not value:failed=true;push_error("R2 CACHE: "+label)
func settle() -> void:
    for i in range(4):await process_frame
func capture() -> Dictionary:
    await settle();lab.effect.request_readback();await settle()
    var result: Dictionary=lab.effect.readback();expect(not result.is_empty(),"Actual GPU readback")
    result["performance"]=lab.effect.performance_snapshot();return result
func apply_case(item: Dictionary) -> void:
    if not item["values"].is_empty():expect(lab.command({"op":"set_values","values":item["values"]})["ok"],item["name"]+" validated command")
    if item.has("ticks"):
        expect(lab.command({"op":"advance","ticks":item["ticks"]})["ok"],"Queued actual physics ticks")
        for i in range(100):
            await physics_frame
            if lab._queued_ticks==0:break
        expect(lab._queued_ticks==0,"Actual locomotion completed")
func gpu_ms(performance: Dictionary) -> float:
    return float(performance["lie_gpu_ns"])/1000000.0 if performance.has("lie_gpu_ns") else -1
func compare(reference: Dictionary,actual: Dictionary,label: String) -> Dictionary:
    var a: PackedFloat32Array=reference["color"];var b: PackedFloat32Array=actual["color"]
    var large: int=0;var total: float=0;var maximum: float=0;var alpha_different: int=0
    for i in range(a.size()):
        if not is_finite(b[i]):failed=true;break
        var error: float=absf(a[i]-b[i]);total+=error;maximum=maxf(maximum,error)
        if error>.02:large+=1
        if i%4==3 and error>.1:alpha_different+=1
    var da: PackedFloat32Array=reference["depth"].to_byte_array().to_float32_array()
    var db: PackedFloat32Array=actual["depth"].to_byte_array().to_float32_array()
    var depth_large: int=0;var depth_max: float=0
    for i in range(da.size()):
        if da[i]<100 or db[i]<100:
            var error: float=absf(da[i]-db[i]);depth_max=maxf(depth_max,error)
            if error>.001:depth_large+=1
    # Small roundoff may change ties at capture silhouettes. Full-frame errors
    # and ownership mismatches are bounded independently, never hidden by SSIM.
    expect(total/a.size()<.00005,label+" mean color equivalence")
    expect(large<float(a.size())*.0002,label+" material equivalence")
    expect(alpha_different<10,label+" coverage equivalence")
    expect(depth_large<float(da.size())*.0001,label+" depth/occlusion equivalence")
    return {"mean_color_error":total/a.size(),"max_color_error":maximum,"color_channels_error_gt_02":large,"alpha_mismatches":alpha_different,"depth_mismatches_gt_1mm":depth_large,"max_depth_error":depth_max}
func run() -> void:
    root.size=Vector2i(1280,720)
    var references: Array=[]
    lab=ReferenceLab.new();lab.touch_mode=true;root.add_child(lab);await settle()
    expect(lab.effect.gpu_ready,"Legacy shader on actual Vulkan")
    for item in cases:
        await apply_case(item);references.append(await capture())
    root.remove_child(lab);lab.free();await settle()
    lab=Lab.new();lab.touch_mode=true;root.add_child(lab);await settle()
    expect(lab.effect.gpu_ready,"Cached shader on actual Vulkan")
    for index in range(cases.size()):
        var item: Dictionary=cases[index];await apply_case(item)
        var actual: Dictionary=await capture();var perf: Dictionary=actual["performance"];var cache: Dictionary=perf.get("cache",{})
        var result: Dictionary=compare(references[index],actual,item["name"])
        result.merge({"case":item["name"],"cache":cache,"reference_gpu_ms":gpu_ms(references[index]["performance"]),"cached_gpu_ms":gpu_ms(perf),"passes_ms":perf.get("gpu_pass_ms_last",{})})
        results.append(result);print("CACHE CASE ",JSON.stringify(result))
        expect(actual["asset_uploads"]==1,"One immutable bank upload")
        if item["name"]=="camera":
            expect(cache["transformed_samples_last"]==0 and not cache["combined_shadow_rebuilt_last"],"Orbit reuses world transforms and shadows")
        if item["name"]=="grip":
            expect(cache["transformed_samples_last"]>0 and cache["reused_world_samples_last"]>0 and not cache["static_shadow_rebuilt_last"],"Pose reuses house geometry/static shadow")
        if item["name"]=="power":
            expect(not cache["raster_rebuilt_last"] and not cache["combined_shadow_rebuilt_last"],"Power reuses depth/materials and shadows")
        if item["name"]=="roof":expect(cache["static_shadow_rebuilt_last"],"Roof invalidates static shadow")
        if item["name"]=="shadows_off":expect(not cache["combined_shadow_rebuilt_last"],"Disabled shadows do no shadow reconstruction")
        if item["name"]=="shadows_on":expect(cache["combined_shadow_rebuilt_last"],"Shadows invalidate after geometry changes while disabled")
        if item["name"]=="walk":expect(cache["reused_world_samples_last"]>0 and not cache["static_shadow_rebuilt_last"],"Actual walking reuses house")
    var before: int=lab.effect.frame_count;await settle();expect(lab.effect.frame_count==before,"Unchanged whole-frame reuse remains")
    var final: Dictionary=lab.effect.performance_snapshot();expect(final.get("gpu_pass_recent",{}).has("project_depth") and final.get("gpu_pass_ms_last",{}).has("shade"),"Real per-pass GPU markers available, including skipped final raster pass")
    var report: Dictionary={"checks":checks,"failed":failed,"cases":results,"device":final.get("device",""),"bank_sha256":lab.effect.catalog["sha256"],"allocation_bytes":lab.effect.allocation_bytes,"physical_android_tested":false,"note":"Actual software Vulkan; pre-cache shader is an unchanged test-only fixture. Timing is not a Mali/Android speed claim."}
    var file:=FileAccess.open("res://robot-cache-verification.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close();print("R2 CACHE ",JSON.stringify({"checks":checks,"failed":failed,"device":report["device"]}))
    await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://robot-cache-preview.png")
    root.remove_child(lab);lab.free();await process_frame;quit(1 if failed else 0)
