extends SceneTree
const Rigid=preload("res://lie15_model.gd")
const Baseline=preload("res://lie15_capture_effect.gd")
const Quality=preload("res://lie16_capture_effect.gd")
const Fixture=preload("res://lie16_temporal_fixture.gd")
const ColorFixture=preload("res://lie16_color_fixture.gd")
var failed: bool=false
var lab: Node3D
var effect: CompositorEffect
var lighting: CompositorEffect

func _initialize() -> void: call_deferred("_run")
func _settle(count: int=3) -> void:
    for i in range(count): await process_frame
func _fail(message: String) -> void:
    failed=true; push_error("LIE16 FAIL: "+message); quit(1)
func _snapshot(target: CompositorEffect=effect) -> Dictionary:
    target.call("request_readback")
    for i in range(180):
        await process_frame
        var result: Dictionary=target.call("readback")
        if not result.is_empty(): return result
    return {}
func _save(name: String) -> void:
    get_root().get_texture().get_image().save_png("res://lie16-"+name+".png")
func _buffer_image(values: PackedFloat32Array,name: String,size: int) -> void:
    var image:=Image.create_from_data(size,size,false,Image.FORMAT_RGBAF,values.to_byte_array())
    image.convert(Image.FORMAT_RGBA8)
    image.save_png("res://lie16-"+name+".png")
func _meshes(node: Node) -> int:
    var result: int=1 if node is MeshInstance3D and (node as MeshInstance3D).is_visible_in_tree() else 0
    for child in node.get_children(): result+=_meshes(child)
    return result

func _geometry(actual: Dictionary,name: String) -> Dictionary:
    var file:=FileAccess.open("res://captures/robot_master/reference-"+name+"-owners.bin",FileAccess.READ)
    var expected: PackedByteArray=file.get_buffer(file.get_length())
    file=FileAccess.open("res://captures/robot_master/reference-"+name+"-depth.bin",FileAccess.READ)
    var reference_depth: PackedFloat32Array=file.get_buffer(file.get_length()).to_float32_array()
    var owners: PackedInt32Array=actual["owners"]
    var depths: PackedFloat32Array=(actual["depth"] as PackedInt32Array).to_byte_array().to_float32_array()
    var intersection: int=0
    var union_count: int=0
    var matching: int=0
    var error: float=0
    var holes: int=0
    for i in range(owners.size()):
        var a: bool=owners[i]>=0 and owners[i]<Rigid.PARTS
        var b: bool=expected[i]<Rigid.PARTS
        if a and b: intersection+=1
        if a or b: union_count+=1
        if a and b and owners[i]==int(expected[i]): error+=absf(depths[i]-reference_depth[i]); matching+=1
        if expected[i]>=Rigid.PARTS and expected[i]<=Rigid.PARTS+1 and owners[i]<0: holes+=1
    return {"body_silhouette_iou":float(intersection)/maxi(union_count,1),"mean_body_depth_error_m":error/maxi(matching,1),"receiver_holes":holes}

func _camera(config: Dictionary) -> void:
    lab.call("set_scenario",config.get("pose","bounce"))
    lab.set("yaw_degrees",float(config.get("yaw",24)))
    lab.set("elevation_degrees",float(config.get("elevation",10)))
    lab.set("distance_scale",float(config.get("distance_scale",1)))
    lab.call("move_camera")

func _profile_summary(rows: Array) -> Dictionary:
    var times: Array=[]
    var cpu: Array=[]
    for row in rows.slice(maxi(0,rows.size()-12)):
        times.append(float(row["consumer_gpu_ms"])); cpu.append(float(row["cpu_prepare_us"])/1000)
    times.sort(); cpu.sort()
    return {"samples":times.size(),"median_consumer_gpu_ms":times[int(times.size()/2)] if not times.is_empty() else null,
        "median_cpu_prepare_ms":cpu[int(cpu.size()/2)] if not cpu.is_empty() else null,"raw_samples":rows.slice(maxi(0,rows.size()-12)),
        "scope":"capture reconstruction, temporal resolve and viewport composition; excludes light transport and CPU pose graph"}

func _run() -> void:
    var color_fixtures: Dictionary=ColorFixture.run()
    if color_fixtures.has("error"): _fail(str(color_fixtures)); return
    for name in color_fixtures:
        if float(color_fixtures[name]["maximum_error"])>.000002: _fail("Weak-coverage color oracle "+name+": "+str(color_fixtures[name])); return
    var fixtures: Dictionary=Fixture.run()
    if fixtures.has("error"): _fail(str(fixtures)); return
    for name in fixtures:
        if float(fixtures[name]["maximum_center_error"])>.000002: _fail("Independent temporal shader oracle "+name+": "+str(fixtures[name])); return
    if int(fixtures["articulated_owner"]["accepted_history_pixels"])==0 or int(fixtures["other_owner"]["wrong_owner"])==0: _fail("Temporal owner / rigid movement guards did not execute"); return
    var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://captures/robot_master/robot-reference.json"))
    lab=load("res://lie16_lab.tscn").instantiate()
    get_root().add_child(lab)
    lab.set_process(false)
    effect=lab.get("effect"); lighting=lab.get("lighting")
    effect.call("configure_quality",false,false,true,false)
    for i in range(240):
        await process_frame
        if bool(effect.get("gpu_ready")) and int(effect.get("frame_count"))>3: break
    if not bool(effect.get("gpu_ready")) or _meshes(lab)!=0: _fail("Captured-only robot failed: "+str(effect.get("failure"))); return
    (lab.get("ui") as CanvasLayer).visible=false
    # Original radiometry remains unchanged; quality never bakes extra lights.
    var radiometry: Dictionary={}
    for name in ["bounce","pose","light","absorbing","dark"]:
        _camera({"pose":name})
        await _settle()
        var actual: Dictionary=await _snapshot()
        if actual.is_empty(): _fail("Readback timeout"); return
        var expected: Dictionary=reference["scenarios"][name]
        var probes: PackedFloat32Array=actual["probes"]
        var error: float=0
        for i in range(Rigid.PARTS*6):
            for c in range(3): error=maxf(error,absf(probes[i*8+4+c]-float(expected["probes"][i]["display"][c])))
        if error>.001: _fail("Material oracle "+name+" error="+str(error)); return
        radiometry[name]={"maximum_probe_display_error":error}
    var geometry: Dictionary={}
    var work: Dictionary={}
    for name in ["base","front","pose","orbit","high","close","far"]:
        var config: Dictionary=reference["geometry"][name]
        _camera(config)
        effect.call("configure_quality",false,false,true,false)
        await _settle()
        var full: Dictionary=await _snapshot()
        _save("full-"+name)
        effect.call("configure_quality",true,false,true,false)
        await _settle()
        var adaptive: Dictionary=await _snapshot()
        _save("adaptive-"+name)
        var a: Dictionary=_geometry(adaptive,name)
        var b: Dictionary=_geometry(full,name)
        if float(a["body_silhouette_iou"])<.88 or float(a["mean_body_depth_error_m"])>.055 or int(a["receiver_holes"])!=0: _fail("Geometry "+name+": "+str(a)); return
        if float(a["body_silhouette_iou"])<float(b["body_silhouette_iou"])-.025: _fail("Adaptive silhouette regressed "+name+": "+str(a)+" full="+str(b)); return
        geometry[name]={"full":b,"adaptive":a}
        var raw_a: PackedFloat32Array=adaptive["raw_color"]
        var raw_b: PackedFloat32Array=full["raw_color"]
        var squared: float=0
        var maximum: float=0
        for i in range(raw_a.size()):
            if i%4==3: continue
            var delta: float=absf(raw_a[i]-raw_b[i]); squared+=delta*delta; maximum=maxf(maximum,delta)
        work[name]={"full_sample_invocations":full["sample_invocations"],"adaptive_sample_invocations":adaptive["sample_invocations"],
            "full_shades":full["counters"][1],"adaptive_shades":adaptive["counters"][1],"lod_sample_counts":Array(adaptive["lod_sample_counts"]),
            "color_rmse":sqrt(squared/(raw_a.size()*.75)),"maximum_color_difference":maximum,
            "adaptive_consumer_bytes":adaptive["allocation_bytes"],"projected_bytes":adaptive["projected_bytes"],"cross_owner_contributions_rejected":adaptive["counters"][4]}
    if int(work["far"]["adaptive_sample_invocations"])>=int(work["far"]["full_sample_invocations"]): _fail("Adaptive sampling did not avoid work at distance"); return
    # Static scene: temporal jitter is tested against the RAW samples from the
    # same jittered frames. Only pixels retaining their owner enter this metric.
    _camera({})
    effect.call("configure_quality",true,true,true,true)
    await _settle(8)
    var sums_raw:=PackedFloat64Array(); sums_raw.resize(384*384*3)
    var squares_raw:=PackedFloat64Array(); squares_raw.resize(sums_raw.size())
    var sums_resolved:=PackedFloat64Array(); sums_resolved.resize(sums_raw.size())
    var squares_resolved:=PackedFloat64Array(); squares_resolved.resize(sums_raw.size())
    var stable: PackedInt32Array
    var static_samples: int=16
    var history_accepted: int=0
    for frame in range(static_samples):
        await _settle(1)
        var actual: Dictionary=await _snapshot()
        if frame==0: stable=(actual["owners"] as PackedInt32Array).duplicate()
        var raw: PackedFloat32Array=actual["raw_color"]
        var resolved: PackedFloat32Array=actual["color"]
        var owners: PackedInt32Array=actual["owners"]
        history_accepted+=int(actual["counters"][8])
        for pixel in range(stable.size()):
            if stable[pixel]!=owners[pixel]: stable[pixel]=-1
            if stable[pixel]<0 or stable[pixel]>=Rigid.PARTS: continue
            for c in range(3):
                var index: int=pixel*3+c
                var a: float=raw[pixel*4+c]; var b: float=resolved[pixel*4+c]
                sums_raw[index]+=a; squares_raw[index]+=a*a
                sums_resolved[index]+=b; squares_resolved[index]+=b*b
        if frame in [0,7,15]:
            _buffer_image(raw,"static-raw-%02d" % frame,384)
            _buffer_image(resolved,"static-resolved-%02d" % frame,384)
    var raw_variance: float=0
    var resolved_variance: float=0
    var channels: int=0
    for pixel in range(stable.size()):
        if stable[pixel]<0 or stable[pixel]>=Rigid.PARTS: continue
        for c in range(3):
            var index: int=pixel*3+c
            raw_variance+=maxf(0,squares_raw[index]/static_samples-pow(sums_raw[index]/static_samples,2))
            resolved_variance+=maxf(0,squares_resolved[index]/static_samples-pow(sums_resolved[index]/static_samples,2))
            channels+=1
    raw_variance/=maxi(channels,1); resolved_variance/=maxi(channels,1)
    if history_accepted==0 or resolved_variance>=raw_variance: _fail("Temporal stability failed raw="+str(raw_variance)+" resolved="+str(resolved_variance)); return
    var temporal: Dictionary={"static_frames":static_samples,"stable_body_channels":channels,"raw_mean_rgb_variance":raw_variance,
        "resolved_mean_rgb_variance":resolved_variance,"accepted_history_pixels_over_sequence":history_accepted,"numeric_shader_fixtures":fixtures}
    # Light changes invalidate history, including the visible decorative eyes.
    var before: Dictionary=await _snapshot()
    _camera({"pose":"dark"})
    await _settle(2)
    var dark: Dictionary=await _snapshot()
    if int(dark["history_resets"])<=int(before["history_resets"]): _fail("Changed light/material codes retained history"); return
    temporal["light_change_history_reset"]=true
    _save("dark-after-light-change")
    # A cut to a camera pointing away cannot retain a single robot pixel.
    var camera: Camera3D=lab.get("camera")
    camera.look_at(camera.position+Vector3.RIGHT)
    await _settle(2)
    var away: Dictionary=await _snapshot()
    var stale: int=0
    for owner in away["owners"]:
        if int(owner)>=0 and int(owner)<Rigid.PARTS: stale+=1
    if int(away["active_view_tasks"])!=0 or stale!=0: _fail("Stale robot after camera cut"); return
    temporal["offscreen_stale_body_pixels"]=stale
    _save("camera-away")
    # Time the same consumer at a far camera; no readbacks or PNG writes inside
    # the measured frames. These are driver timestamps on software Vulkan.
    _camera({"distance_scale":1.5})
    effect.set("profile_enabled",true)
    var timings: Dictionary={}
    for mode in ["full","adaptive","adaptive-temporal"]:
        effect.call("configure_quality",mode!="full",mode=="adaptive-temporal",true,mode=="adaptive-temporal")
        var wall_start: int=Time.get_ticks_usec()
        await _settle(20)
        var actual: Dictionary=await _snapshot()
        timings[mode]=_profile_summary(actual["profile"])
        var wall_elapsed_ms: float=float(Time.get_ticks_usec()-wall_start)/1000
        timings[mode]["measured_block_wall_ms"]=wall_elapsed_ms
        if int(timings[mode]["samples"])<8 or float(timings[mode]["median_consumer_gpu_ms"])>wall_elapsed_ms: _fail("Missing / incorrectly scaled driver timestamps "+mode); return
    effect.set("profile_enabled",false)
    # Two real frame sequences use identical authored camera/pose samples.
    # Output cadence is chosen for viewing; it never represents hardware FPS.
    var baseline: CompositorEffect=Baseline.new()
    baseline.set("lighting",lighting)
    var frames: int=48
    for mode in ["baseline","quality"]:
        (lab.get("world") as WorldEnvironment).compositor.compositor_effects=[lighting,baseline if mode=="baseline" else effect]
        if mode=="quality": effect.call("reset_history"); effect.call("configure_quality",true,true,true,true)
        for frame in range(frames):
            var phase: float=TAU*float(frame)/frames
            lab.set("scenario_name","bounce")
            lab.set("elapsed",phase)
            lab.set("yaw_degrees",10.0+float(frame)*90.0/frames)
            lab.set("elevation_degrees",10.0+8*sin(phase))
            lab.set("distance_scale",1.05+.15*sin(phase))
            lab.call("apply_pose"); lab.call("move_camera")
            if mode=="baseline": baseline.call("set_poses",lab.get("poses"))
            await _settle(4 if frame==0 else 2)
            _save("motion-"+mode+"-%02d" % frame)
    var final: Dictionary=await _snapshot()
    if int(final["asset_uploads"])!=1 or _meshes(lab)!=0: _fail("Master duplication or visible source geometry during movement"); return
    baseline.call("shutdown")
    # A larger image is a separate allocation/preset, still using the same
    # capture bundle. It is not described as newly captured source detail.
    var high: CompositorEffect=Quality.new(576)
    high.set("lighting",lighting); high.call("set_poses",lab.get("poses"))
    (lab.get("world") as WorldEnvironment).compositor.compositor_effects=[lighting,high]
    await _settle(5)
    var high_data: Dictionary=await _snapshot(high)
    if high_data.is_empty() or not bool(high.get("gpu_ready")): _fail("Higher reconstruction preset failed"); return
    _save("higher-resolution")
    (lab.get("world") as WorldEnvironment).compositor.compositor_effects=[lighting,effect]
    high.call("shutdown")
    var report: Dictionary={"experiment":"LIE16-stable-quality-v1","device":final["device"],"hardware_fps_claim":false,
        "visible_source_meshes":0,"source_capture_resolution":128,"default_reconstruction_size":384,"higher_reconstruction_size":576,
        "capture_views":60,"lighting_capture_variants":0,"immutable_master_uploads_after_motion":final["asset_uploads"],
        "conservative_level_sample_counts":effect.get("master")["level_sample_counts"],"radiometry":radiometry,
        "numeric_color_fixtures":color_fixtures,
        "geometry_against_original_triangles":geometry,"adaptive_work_and_image_error":work,"temporal":temporal,
        "consumer_timestamp_measurements":timings,"paired_real_motion_frames":frames,
        "higher_resolution_consumer_bytes":high_data["allocation_bytes"],"known_limits":["software Vulkan is not physical GPU / Android performance",
        "conservative captured mips approximate source detail; fades may temporarily dispatch two levels","history is bounded, reactive and owner/depth rejected but not a guarantee for all future assets",
        "oriented-box shadows and coarse diffuse indirect lighting are unchanged","four-tap spatial reconstruction softens edges and cannot restore missing capture detail",
        "higher resolution allocates a separate consumer; 128px source captures stay unchanged"]}
    var file:=FileAccess.open("res://lie16-diagnostic.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  "))
    print("LIE16 PASS ",JSON.stringify(report))
    lab.queue_free(); await _settle(3); quit(0)
