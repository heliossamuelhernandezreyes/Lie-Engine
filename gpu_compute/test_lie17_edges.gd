extends SceneTree
const Fixture=preload("res://lie17_edge_fixture.gd")
const Rigid=preload("res://lie15_model.gd")
var lab: Node3D
var effect: CompositorEffect

func _initialize() -> void: call_deferred("_run")
func _settle(count: int=3) -> void:
    for i in range(count): await process_frame
func _fail(message: String) -> void:
    push_error("LIE17 FAIL: "+message); quit(1)
func _snapshot() -> Dictionary:
    effect.call("request_readback")
    for i in range(180):
        await process_frame
        var result: Dictionary=effect.call("readback")
        if not result.is_empty(): return result
    return {}
func _save(name: String) -> void:
    get_root().get_texture().get_image().save_png("res://lie17-"+name+".png")
func _meshes(node: Node) -> int:
    var result: int=1 if node is MeshInstance3D and (node as MeshInstance3D).is_visible_in_tree() else 0
    for child in node.get_children(): result+=_meshes(child)
    return result

func _run() -> void:
    var fixtures: Dictionary=Fixture.run()
    if fixtures.has("error"): _fail(str(fixtures)); return
    var before_error: float=0
    var after_error: float=0
    for name in fixtures:
        if str(name).begins_with("diagonal_"):
            before_error+=float(fixtures[name]["disabled"]["rmse"])
            after_error+=float(fixtures[name]["enabled"]["rmse"])
        elif float(fixtures[name]["enabled"]["maximum_error"])>.001:
            _fail("Depth/flat/feature oracle "+str(name)+": "+str(fixtures[name])); return
    if after_error>=before_error: _fail("Analytic diagonal area did not improve: "+str(fixtures)); return
    lab=load("res://lie17_lab.tscn").instantiate()
    get_root().add_child(lab); lab.set_process(false)
    effect=lab.get("effect")
    # Match the raw spatial input in both recordings, isolating the edge pass.
    # The interactive default still enables Lie's rigid temporal reconstruction.
    effect.call("configure_quality",true,false,true,false)
    for i in range(240):
        await process_frame
        if bool(effect.get("gpu_ready")) and int(effect.get("frame_count"))>3: break
    if not bool(effect.get("gpu_ready")) or _meshes(lab)!=0: _fail("Captured-only consumer failed"); return
    (lab.get("ui") as CanvasLayer).visible=false
    lab.call("set_scenario","bounce")
    var timings: Array=[]
    effect.set("profile_enabled",true)
    # Off/on/off permits inspection of drift; no FPS or blanket speed claim.
    for enabled in [false,true,false]:
        effect.call("set_edge_aa",enabled)
        var started: int=Time.get_ticks_usec()
        await _settle(24)
        var actual: Dictionary=await _snapshot()
        var elapsed_ms: float=float(Time.get_ticks_usec()-started)/1000
        var rows: Array=actual["profile"]
        var times: Array=[]
        for row in rows.slice(maxi(0,rows.size()-12)): times.append(float(row["consumer_gpu_ms"]))
        times.sort()
        if times.size()<8 or float(times[int(times.size()/2)])>elapsed_ms: _fail("Missing or incorrectly scaled measured consumer intervals"); return
        timings.append({"edge_enabled":enabled,"median_consumer_gpu_ms":times[int(times.size()/2)],"measured_block_wall_ms":elapsed_ms,"raw_samples":rows.slice(maxi(0,rows.size()-12))})
    effect.set("profile_enabled",false)
    var states: Dictionary={}
    for state in ["bounce","pose","light","dark"]:
        lab.call("set_scenario",state)
        for enabled in [false,true]:
            effect.call("set_edge_aa",enabled)
            await _settle()
            _save(state+("-on" if enabled else "-off"))
        states[state]="matched camera, pose and spatial input"
    var frames: int=48
    for mode in ["off","on"]:
        effect.call("set_edge_aa",mode=="on")
        for frame in range(frames):
            var phase: float=TAU*float(frame)/frames
            lab.set("scenario_name","bounce"); lab.set("elapsed",phase)
            lab.set("yaw_degrees",10.0+float(frame)*90.0/frames)
            lab.set("elevation_degrees",10.0+8*sin(phase))
            lab.set("distance_scale",1.05+.15*sin(phase))
            lab.call("apply_pose"); lab.call("move_camera")
            await _settle(4 if frame==0 else 2)
            _save("motion-"+mode+"-%02d" % frame)
    var final: Dictionary=await _snapshot()
    if final.is_empty() or int(final["asset_uploads"])!=1 or _meshes(lab)!=0: _fail("Invalid final master / geometry state"); return
    effect.call("configure_quality",true,true,true,true)
    await _settle(8)
    var combined: Dictionary=await _snapshot()
    if combined.is_empty() or int(combined["counters"][8])<=0 or int(combined["asset_uploads"])!=1:
        _fail("Combined contrast filter and rigid temporal history failed"); return
    _save("combined-temporal")
    var report: Dictionary={"experiment":"LIE17-contrast-edges-v1","device":final["device"],"hardware_fps_claim":false,
        "visible_source_meshes":0,"source_capture_resolution":128,"reconstruction_size":384,"output_size":768,
        "analytic_diagonal_mean_rmse_without_filter":before_error/3,"analytic_diagonal_mean_rmse_with_filter":after_error/3,
        "production_shader_fixtures":fixtures,"consumer_timestamp_measurements":timings,"matched_states":states,
        "paired_real_motion_frames":frames,"motion_temporal_enabled":false,"interactive_temporal_default":true,
        "combined_temporal_accepted_pixels":combined["counters"][8],
        "immutable_master_uploads":final["asset_uploads"],"consumer_bytes":final["allocation_bytes"],
        "extra_image_buffers":0,"known_limits":["The filter adds texture reads; it is not free", "Softening can remove fine detail",
        "Direction is bounded to two source pixels; not a replacement for higher-resolution captures",
        "Software Vulkan is not physical GPU or Android timing", "Motion comparison isolates spatial edge filtering with temporal disabled"]}
    var file:=FileAccess.open("res://lie17-diagnostic.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  "))
    print("LIE17 PASS ",JSON.stringify(report))
    lab.queue_free(); await _settle(3); quit(0)
