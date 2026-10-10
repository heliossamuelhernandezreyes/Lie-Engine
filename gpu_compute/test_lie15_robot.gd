extends SceneTree
const Rigid=preload("res://lie15_model.gd")
const Capture=preload("res://lie15_capture_effect.gd")
var failed: bool=false
func _initialize() -> void: call_deferred("_run")
func _settle(count: int=5) -> void:
    for i in range(count): await process_frame
func _snapshot(effect: CompositorEffect) -> Dictionary:
    effect.call("request_readback")
    for i in range(180):
        await process_frame
        var data: Dictionary=effect.call("readback")
        if not data.is_empty(): return data
    return {}
func _fail(message: String) -> void:
    failed=true
    push_error("LIE15 FAIL: "+message)
    quit(1)
func _save(name: String) -> void:
    get_root().get_texture().get_image().save_png("res://lie15-"+name+".png")
func _meshes(node: Node) -> int:
    var count: int=1 if node is MeshInstance3D and (node as MeshInstance3D).is_visible_in_tree() else 0
    for child in node.get_children(): count+=_meshes(child)
    return count
func _run() -> void:
    var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://captures/robot_master/robot-reference.json"))
    if reference.is_empty(): _fail("Missing float64 and original-mesh oracle"); return
    var lab: Node3D=load("res://lie15_lab.tscn").instantiate()
    get_root().add_child(lab)
    var effect: CompositorEffect=lab.get("effect")
    var lighting: CompositorEffect=lab.get("lighting")
    for i in range(240):
        await process_frame
        if bool(effect.get("gpu_ready")) and int(effect.get("frame_count"))>3: break
    if not bool(effect.get("gpu_ready")) or _meshes(lab)!=0: _fail("Captured robot requires zero visible source meshes: "+str(effect.get("failure"))); return
    (lab.get("ui") as CanvasLayer).visible=false
    var cases: Dictionary={}
    var device: String=""
    for name in ["direct","bounce","pose","light","absorbing","dark"]:
        lab.call("set_scenario",name)
        await _settle()
        lighting.call("request_readback")
        var actual_light: Dictionary={}
        for i in range(180):
            await process_frame
            actual_light=lighting.call("readback")
            if not actual_light.is_empty(): break
        var actual: Dictionary=await _snapshot(effect)
        if actual.is_empty() or actual_light.is_empty(): _fail("Readback timeout"); return
        device=str(actual_light["device"])
        var expected: Dictionary=reference["scenarios"][name]
        var irradiance: PackedFloat32Array=actual_light["irradiance"]
        var probes: PackedFloat32Array=actual["probes"]
        var node_error: float=0
        var direct_error: float=0
        var display_error: float=0
        for i in range((expected["irradiance"] as Array).size()):
            for c in range(3): node_error=maxf(node_error,absf(irradiance[i*4+c]-float(expected["irradiance"][i][c])))
        for i in range(Rigid.PARTS*6):
            for c in range(3):
                direct_error=maxf(direct_error,absf(probes[i*8+c]-float(expected["probes"][i]["direct"][c])))
                display_error=maxf(display_error,absf(probes[i*8+4+c]-float(expected["probes"][i]["display"][c])))
            if roundi(probes[i*8+3])!=int(expected["probes"][i]["node"]): _fail("Unstable sample-node association"); return
        var poses: Array[Transform3D]=lab.get("poses")
        var bodies: Array[StaticBody3D]=lab.get("bodies")
        var transform_error: float=0
        for i in range(Rigid.PARTS):
            transform_error=maxf(transform_error,bodies[i].global_position.distance_to(poses[i].origin))
            for k in range(3): transform_error=maxf(transform_error,poses[i].basis[k].distance_to(Rigid.Model.vector(expected["instances"][i]["basis"][k])))
        if node_error>.003:
            var factors: PackedFloat32Array=Rigid.Model.factor_bytes(lab.get("model")).to_float32_array()
            var n: int=(expected["irradiance"] as Array).size()
            var factor_error: float=0
            for i in range(n):
                for j in range(n): factor_error=maxf(factor_error,absf(factors[i*n+j]-float(expected["factors"][i][j])))
                for c in range(3):
                    if absf(irradiance[i*4+c]-float(expected["irradiance"][i][c]))>.003: print("LIE15 NODE DIFF ",name," node=",i," expected=",expected["irradiance"][i]," actual=",irradiance.slice(i*4,i*4+3)," patch=",lab.get("model")["patches"][i])
            print("LIE15 FACTOR MAX DIFF ",factor_error)
        if node_error>.003 or direct_error>.003 or display_error>.001 or transform_error>.00001:
            _fail(name+" numerical oracle node="+str(node_error)+" direct="+str(direct_error)+" display="+str(display_error)+" transform="+str(transform_error)); return
        cases[name]={"maximum_node_error":node_error,"maximum_pixel_direct_error":direct_error,"maximum_pixel_display_error":display_error,"maximum_transform_error_m":transform_error}
        _save(name)
    var geometry: Dictionary={}
    for name in ["base","front","pose","orbit","high","close","far"]:
        var config: Dictionary=reference["geometry"][name]
        lab.call("set_scenario",config["pose"])
        lab.set("yaw_degrees",float(config["yaw"]))
        lab.set("elevation_degrees",float(config["elevation"]))
        lab.set("distance_scale",float(config["distance_scale"]))
        lab.call("move_camera")
        await _settle()
        var actual: Dictionary=await _snapshot(effect)
        var owner_file: FileAccess=FileAccess.open("res://captures/robot_master/reference-"+name+"-owners.bin",FileAccess.READ)
        var expected_owners: PackedByteArray=owner_file.get_buffer(owner_file.get_length())
        var depth_file: FileAccess=FileAccess.open("res://captures/robot_master/reference-"+name+"-depth.bin",FileAccess.READ)
        var expected_depth: PackedFloat32Array=depth_file.get_buffer(depth_file.get_length()).to_float32_array()
        var owners: PackedInt32Array=actual["owners"]
        var depth: PackedFloat32Array=(actual["depth"] as PackedInt32Array).to_byte_array().to_float32_array()
        var intersection: int=0
        var union_count: int=0
        var depth_error: float=0
        var matching: int=0
        var body_pixels: int=0
        var receiver_holes: int=0
        for i in range(owners.size()):
            var a: bool=owners[i]>=0 and owners[i]<Rigid.PARTS
            var b: bool=expected_owners[i]<Rigid.PARTS
            if a: body_pixels+=1
            if expected_owners[i]>=Rigid.PARTS and expected_owners[i]<=Rigid.PARTS+1 and owners[i]<0: receiver_holes+=1
            if a or b: union_count+=1
            if a and b: intersection+=1
            if a and b and owners[i]==int(expected_owners[i]): depth_error+=absf(depth[i]-expected_depth[i]); matching+=1
        var iou: float=float(intersection)/maxi(union_count,1)
        depth_error/=maxi(matching,1)
        if iou<.80 or depth_error>.055 or receiver_holes>0: _fail(name+" original mesh mismatch IoU="+str(iou)+" depth="+str(depth_error)+" holes="+str(receiver_holes)); return
        geometry[name]={"body_silhouette_iou":iou,"mean_body_depth_error_m":depth_error,"body_pixels":body_pixels,"receiver_holes":receiver_holes}
        _save("camera-"+name)
    var ratio: float=float(geometry["far"]["body_pixels"])/float(geometry["base"]["body_pixels"])
    if ratio<.30 or ratio>.58: _fail("XYZ perspective scale did not change apparent size"); return
    # Compare the SAME camera and material, against padded / unconditional work.
    # Integer color accumulation makes visual equivalence deterministic.
    lab.call("set_scenario","bounce")
    lab.set("yaw_degrees",24.0)
    lab.set("elevation_degrees",10.0)
    lab.set("distance_scale",1.0)
    lab.call("move_camera")
    await _settle()
    var optimized: Dictionary=await _snapshot(effect)
    _save("optimized")
    var baseline: CompositorEffect=Capture.new(false)
    baseline.set("lighting",lighting)
    baseline.call("set_poses",lab.get("poses"))
    (lab.get("world") as WorldEnvironment).compositor.compositor_effects=[lighting,baseline]
    await _settle(8)
    var padded: Dictionary=await _snapshot(baseline)
    if padded.is_empty(): _fail("Baseline did not render"); return
    _save("baseline")
    var max_color_difference: float=0
    var optimized_colors: PackedFloat32Array=optimized["color"]
    var padded_colors: PackedFloat32Array=padded["color"]
    for i in range(optimized_colors.size()): max_color_difference=maxf(max_color_difference,absf(optimized_colors[i]-padded_colors[i]))
    if max_color_difference>0 or optimized["depth"]!=padded["depth"] or optimized["owners"]!=padded["owners"]: _fail("Optimization changed color / depth / owner"); return
    if int(optimized["counters"][1])>=int(padded["counters"][1]) or int(optimized["sample_invocations"])>=int(padded["padded_invocations"]): _fail("No measured work reduction"); return
    (lab.get("world") as WorldEnvironment).compositor.compositor_effects=[lighting,effect]
    baseline.call("shutdown")
    baseline=null
    await _settle()
    lab.call("set_reference",true)
    await _settle()
    if _meshes(lab)==0: _fail("Native original-mesh inspection failed"); return
    _save("native-3d-reference")
    lab.call("set_reference",false)
    await _settle()
    if _meshes(lab)!=0: _fail("Native meshes leaked into Lie view"); return
    # Camera behind the scene must clear all points; no stale robot.
    lab.set_process(false)
    var camera: Camera3D=lab.get("camera")
    camera.look_at(camera.position+Vector3.RIGHT)
    await _settle()
    var offscreen: Dictionary=await _snapshot(effect)
    var offscreen_pixels: int=0
    for owner in offscreen["owners"]:
        if int(owner)>=0 and int(owner)<Rigid.PARTS: offscreen_pixels+=1
    if int(offscreen["active_view_tasks"])!=0 or offscreen_pixels!=0: _fail("Offscreen robot was not culled / cleared"); return
    lab.call("move_camera")
    # Actual orbit+motion frames. Pose updates do not upload the master again.
    for i in range(24):
        lab.set("elapsed",float(i)*TAU/24)
        lab.set("yaw_degrees",24.0+float(i)*360/24)
        lab.call("apply_pose")
        lab.call("move_camera")
        await _settle(3)
        _save("motion-%02d" % i)
    var final: Dictionary=await _snapshot(effect)
    if int(final["asset_uploads"])!=1: _fail("Master was duplicated during animation"); return
    var report: Dictionary={"experiment":"LIE15-Arcont-robot-v1","device":device,"visible_source_meshes_in_lie":0,"master_count":1,"rigid_parts":Rigid.PARTS,"capture_views":60,"normal_maps_per_view":1,"lighting_capture_variants":0,"asset_provenance":JSON.parse_string(FileAccess.get_file_as_string("res://assets/lie15/provenance.json")),"radiometry":cases,"geometry_against_original_triangles":geometry,"apparent_area_ratio_at_1_5_distance":ratio,
        "optimization":{"maximum_color_difference":max_color_difference,"depth_identical":true,"owners_identical":true,"selected_sample_invocations":optimized["sample_invocations"],"padded_sample_invocations":padded["padded_invocations"],"optimized_projected_bytes":optimized["projected_bytes"],"padded_projected_bytes":padded["projected_bytes"],"optimized_consumer_bytes":optimized["allocation_bytes"],"padded_consumer_bytes":padded["allocation_bytes"],"candidate_shades":padded["counters"][0],"baseline_shades":padded["counters"][1],"optimized_shades":optimized["counters"][1],"avoided_shades":optimized["counters"][2]},"motion_frames":24,"asset_gpu_uploads_after_motion":final["asset_uploads"],"offscreen_stale_pixels":offscreen_pixels,"hardware_fps_claim":false,"known_limits":["software Vulkan validation; real device timing pending","oriented boxes approximate light occlusion; no intra-part self-shadowing","coarse diffuse indirect light; no specular GI or environment reflections","native Godot reference lighting differs from Lie"]}
    var file:=FileAccess.open("res://lie15-diagnostic.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  "))
    print("LIE15 PASS ",JSON.stringify(report))
    lab.queue_free()
    await _settle(3)
    quit(0)
