extends SceneTree
var failed: bool=false
const Rigid=preload("res://lie14_model.gd")

func _initialize() -> void:
    call_deferred("_run")

func _settle(count: int=6) -> void:
    for i in range(count): await process_frame

func _snapshot(effect: CompositorEffect) -> Dictionary:
    effect.call("request_readback")
    for i in range(120):
        await process_frame
        var result: Dictionary=effect.call("readback")
        if not result.is_empty(): return result
    return {}

func _run() -> void:
    var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://captures/rigid_master/rigid-reference.json"))
    if reference.is_empty():
        _fail("Missing independent float64 master oracle")
        return
    var lab: Node3D=load("res://lie14_lab.tscn").instantiate()
    get_root().add_child(lab)
    var effect: CompositorEffect=lab.get("effect")
    var lighting: CompositorEffect=lab.get("lighting")
    for i in range(180):
        await process_frame
        if bool(effect.get("gpu_ready")) and int(effect.get("frame_count"))>3: break
    if not bool(effect.get("gpu_ready")) or _meshes(lab)!=0:
        _fail("Real master did not render with zero visible source meshes: "+str(effect.get("failure")))
        return
    (lab.get("ui") as CanvasLayer).visible=false
    var frames: Dictionary={}
    var cases: Dictionary={}
    var device: String=""
    var curve_difference: float=0
    for name in ["direct","bounce","pose","light","absorbing","dark"]:
        lab.call("set_scenario",name)
        await _settle()
        lighting.call("request_readback")
        var actual_light: Dictionary={}
        for i in range(120):
            await process_frame
            actual_light=lighting.call("readback")
            if not actual_light.is_empty(): break
        var actual: Dictionary=await _snapshot(effect)
        if actual.is_empty() or actual_light.is_empty():
            _fail("GPU diagnostic timeout")
            return
        device=str(actual_light["device"])
        var expected: Dictionary=reference["scenarios"][name]
        var e: PackedFloat32Array=actual_light["irradiance"]
        var n: int=(expected["irradiance"] as Array).size()
        var node_error: float=0
        for i in range(n):
            for c in range(3): node_error=maxf(node_error,absf(e[i*4+c]-float(expected["irradiance"][i][c])))
        var probes: PackedFloat32Array=actual["probes"]
        var direct_error: float=0
        var color_error: float=0
        for i in range(6):
            for c in range(3):
                direct_error=maxf(direct_error,absf(probes[i*8+c]-float(expected["probes"][i]["direct"][c])))
                color_error=maxf(color_error,absf(probes[i*8+4+c]-float(expected["probes"][i]["display"][c])))
            if roundi(probes[i*8+3])!=int(expected["probes"][i]["node"]):
                _fail("Pixel-to-node association changed with pose")
                return
        if node_error>.003 or direct_error>.002 or color_error>.0003:
            _fail("Rigid light differs from float64: "+name+" node="+str(node_error)+" pixel="+str(direct_error)+" color="+str(color_error))
            return
        if name=="bounce":
            for c in range(3): curve_difference+=absf(probes[c]-probes[8+c])
            if curve_difference<.001 or roundi(probes[3])!=roundi(probes[11]):
                _fail("Two captured normals in the same node did not receive distinct direct lighting")
                return
        var poses: Array[Transform3D]=lab.get("poses")
        var joints: Array[Node3D]=lab.get("joints")
        var transform_error: float=0
        for i in range(3):
            var collider: Node3D=joints[i].get_node("InvisibleRigidPart_%d" % i)
            transform_error=maxf(transform_error,collider.global_position.distance_to(poses[i].origin))
            var world_normal: Vector3=poses[i].basis*Vector3.RIGHT
            var expected_normal: Vector3=Rigid.Model.vector(expected["instances"][i]["basis"][0])
            transform_error=maxf(transform_error,world_normal.distance_to(expected_normal))
        if transform_error>.00001:
            _fail("Invisible skeleton/collision/captured normal transforms disagree")
            return
        frames[name]=get_root().get_texture().get_image()
        _save(frames[name],"lie14-"+name+".png")
        cases[name]={"maximum_node_irradiance_error":node_error,"maximum_pixel_direct_error":direct_error,
            "maximum_pixel_display_error":color_error,"maximum_transform_error_m":transform_error,
            "asset_uploads":actual["asset_uploads"],"active_view_tasks":actual["active_view_tasks"]}
    for name in ["bounce","pose","light","absorbing","dark"]:
        if _difference(frames["direct"],frames[name])<.000001:
            _fail("No visible change: "+name)
            return
    var geometry: Dictionary={}
    for name in ["base","pose","orbit","high","far"]:
        var config: Dictionary=reference["geometry"][name]
        lab.call("set_scenario",config["pose"])
        lab.set("yaw_degrees",float(config["yaw"]))
        lab.set("elevation_degrees",float(config["elevation"]))
        lab.set("distance_scale",float(config["distance_scale"]))
        lab.call("move_camera")
        await _settle()
        var actual: Dictionary=await _snapshot(effect)
        var owner_file: FileAccess=FileAccess.open("res://captures/rigid_master/reference-"+name+"-owners.bin",FileAccess.READ)
        var expected_owners: PackedByteArray=owner_file.get_buffer(owner_file.get_length())
        var depth_file: FileAccess=FileAccess.open("res://captures/rigid_master/reference-"+name+"-depth.bin",FileAccess.READ)
        var expected_depth: PackedFloat32Array=depth_file.get_buffer(depth_file.get_length()).to_float32_array()
        var owners: PackedInt32Array=actual["owners"]
        var depth: PackedFloat32Array=(actual["depth"] as PackedInt32Array).to_byte_array().to_float32_array()
        var intersection: int=0
        var union_count: int=0
        var depth_error: float=0
        var matching: int=0
        var body_pixels: int=0
        var receiver_pixels: int=0
        var receiver_holes: int=0
        for i in range(owners.size()):
            var a: bool=owners[i]>=0 and owners[i]<3
            var b: bool=expected_owners[i]<3
            if a: body_pixels+=1
            if expected_owners[i]>=3 and expected_owners[i]<=4:
                receiver_pixels+=1
                if owners[i]<0: receiver_holes+=1
            if a or b: union_count+=1
            if a and b: intersection+=1
            if a and b and owners[i]==int(expected_owners[i]):
                depth_error+=absf(depth[i]-expected_depth[i])
                matching+=1
        var iou: float=float(intersection)/maxi(union_count,1)
        depth_error/=maxi(matching,1)
        var receiver_hole_fraction: float=float(receiver_holes)/maxi(receiver_pixels,1)
        if iou<.75 or depth_error>.06 or receiver_hole_fraction>.0001:
            _fail("Captured rigid surface disagrees with analytic camera rays: "+name+" IoU="+str(iou)+" depth="+str(depth_error))
            return
        geometry[name]={"body_silhouette_iou":iou,"mean_body_depth_error_m":depth_error,"body_pixels":body_pixels,
            "visible_instances":actual["visible_instances"],"receiver_hole_fraction":receiver_hole_fraction}
        _save(get_root().get_texture().get_image(),"lie14-camera-"+name+".png")
    var area_ratio: float=float(geometry["far"]["body_pixels"])/float(geometry["base"]["body_pixels"])
    if area_ratio<.25 or area_ratio>.65:
        _fail("Perceived size did not follow XYZ perspective")
        return
    lab.call("set_scenario","bounce")
    lab.set("distance_scale",1.0)
    lab.set("elevation_degrees",12.0)
    var previous: Image
    var changes: Array=[]
    for yaw in [29.5,29.75,30.0,30.25,30.5]:
        lab.set("yaw_degrees",yaw)
        lab.call("move_camera")
        await _settle(4)
        var image: Image=get_root().get_texture().get_image()
        if previous!=null: changes.append(_difference(previous,image))
        previous=image
    var largest_change: float=0
    for value in changes: largest_change=maxf(largest_change,float(value))
    if largest_change>.02:
        _fail("Large camera-boundary transition in quarter-degree sweep")
        return
    lab.set("yaw_degrees",0.0)
    lab.call("move_camera")
    effect.call("set_detailed_normals",false)
    await _settle()
    var coarse: Image=get_root().get_texture().get_image()
    _save(coarse,"lie14-coarse-normals.png")
    effect.call("set_detailed_normals",true)
    await _settle()
    var detailed: Image=get_root().get_texture().get_image()
    _save(detailed,"lie14-pixel-normals.png")
    var normal_image_change: float=_difference(coarse,detailed)
    if normal_image_change<.00001:
        _fail("Per-pixel normal refinement did not change actual captured rendering")
        return
    # Native opaque sprite before/behind a captured cylinder must obey depth.
    var poses: Array[Transform3D]=lab.get("poses")
    var center: Vector3=poses[1].origin
    var camera: Camera3D=lab.get("camera")
    var texture:=Image.create(16,16,false,Image.FORMAT_RGBA8)
    texture.fill(Color(0,1,0))
    var sprite:=Sprite3D.new()
    sprite.texture=ImageTexture.create_from_image(texture)
    sprite.pixel_size=.022
    sprite.shaded=false
    sprite.alpha_cut=SpriteBase3D.ALPHA_CUT_DISCARD
    sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED
    sprite.position=center+(camera.position-center)*.5
    lab.add_child(sprite)
    await _settle()
    var front: Image=get_root().get_texture().get_image()
    var uv: Vector2=camera.unproject_position(center)
    var point:=Vector2i(roundi(uv.x),roundi(uv.y))
    point.x=clampi(point.x,0,front.get_width()-1)
    point.y=clampi(point.y,0,front.get_height()-1)
    var green: Color=front.get_pixelv(point)
    if green.g<green.r+.25 or green.g<green.b+.25:
        _fail("Native foreground sprite was overwritten")
        return
    _save(front,"lie14-native-front.png")
    sprite.position=center-(camera.position-center).normalized()*.5
    await _settle()
    var rear: Image=get_root().get_texture().get_image()
    var baseline: Color=detailed.get_pixelv(point)
    var behind: Color=rear.get_pixelv(point)
    var leak: float=absf(baseline.r-behind.r)+absf(baseline.g-behind.g)+absf(baseline.b-behind.b)
    if leak>.01:
        _fail("Rear native sprite leaked through captured cylinder")
        return
    _save(rear,"lie14-native-rear.png")
    sprite.queue_free()
    for i in range(12):
        var t: float=float(i)*TAU/12
        lab.set("angles",[-.55+.3*sin(t),1.2+.4*sin(t*.8),-.7+.35*cos(t*.7)])
        lab.call("apply_pose")
        await _settle(3)
        _save(get_root().get_texture().get_image(),"lie14-motion-%02d.png" % i)
    var final: Dictionary=await _snapshot(effect)
    if int(final["asset_uploads"])!=1:
        _fail("Articulation uploaded duplicate master buffers")
        return
    var report: Dictionary={"experiment":"LIE14-rigid-perception-master-v1","device":device,
        "backend":"software Vulkan; Android performance unmeasured","visible_source_meshes":0,
        "master_count":1,"rigid_instances":3,"camera_views":36,"normal_maps_per_camera_view":1,
        "baked_light_variants_per_view":0,"shared_master_samples":effect.get("master")["sample_count"],
        "asset_uploads":final["asset_uploads"],"consumer_allocation_bytes":final["allocation_bytes"],
        "transport_nodes":(lab.get("model")["patches"] as Array).size(),"scenarios":cases,"geometry":geometry,
        "same_node_captured_normal_direct_difference":curve_difference,
        "quarter_degree_camera_steps_mean_rgb_changes":changes,"maximum_camera_step_mean_rgb_change":largest_change,
        "coarse_vs_pixel_normal_mean_rgb_change":normal_image_change,"perspective_area_ratio_at_1_5x_distance":area_ratio,
        "native_depth_test":"passed","rear_sprite_center_color_leak":leak,
        "limitations":"Three rigid cylinder instances; kinematic joints, not a robotics dynamics solver. Diffuse pixel direct light, node indirect light, finite camera samples, point-splat artifacts, mono perspective. No full Blender editor, opaque metal specular, shared native depth writeback, or hardware speed claim."}
    var file: FileAccess=FileAccess.open("res://lie14-diagnostic.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  "))
    print("LIE-14 PASS ",JSON.stringify(report))
    lab.queue_free()
    await _settle()
    quit(0)

func _difference(a: Image,b: Image) -> float:
    var sum: float=0
    var count: int=0
    for y in range(0,a.get_height(),4):
        for x in range(0,a.get_width(),4):
            var ca: Color=a.get_pixel(x,y)
            var cb: Color=b.get_pixel(x,y)
            sum+=absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)
            count+=3
    return sum/maxi(count,1)

func _meshes(node: Node) -> int:
    var count: int=1 if node is MeshInstance3D and (node as MeshInstance3D).visible else 0
    for child in node.get_children(): count+=_meshes(child)
    return count

func _save(image: Image,name: String) -> void:
    if image.save_png(ProjectSettings.globalize_path("res://"+name))!=OK: _fail("Cannot save evidence")

func _fail(message: String) -> void:
    failed=true
    var image: Image=get_root().get_texture().get_image()
    if image!=null: image.save_png(ProjectSettings.globalize_path("res://lie14-failure.png"))
    printerr("LIE-14 FAIL: ",message)
    quit(1)
