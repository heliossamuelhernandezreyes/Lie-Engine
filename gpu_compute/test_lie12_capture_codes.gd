extends SceneTree
var failed: bool=false

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://captures/coded_shard/light-reference.json"))
    if not parsed is Dictionary:
        _fail("Generate the capture-specific float64 oracle")
        return
    var reference: Dictionary=parsed
    var lab: Node3D=load("res://lie12_lab.tscn").instantiate() as Node3D
    get_root().add_child(lab)
    var effect: CompositorEffect=lab.get("effect")
    var lighting: CompositorEffect=lab.get("lighting")
    for k in range(180):
        await process_frame
        if bool(effect.get("gpu_ready")) and int(effect.get("frame_count"))>4: break
    if not bool(effect.get("capture_loaded")) or not bool(effect.get("gpu_ready")) or _visible_meshes(lab)!=0:
        _fail("Real coded Blender captures did not render without visible source geometry")
        return
    (lab.get("label") as Label).visible=false
    var model: Dictionary=lab.get("base_model")
    var n: int=(model["patches"] as Array).size()
    var cases: Dictionary={}
    var frames: Dictionary={}
    var device: String=""
    for name in ["direct","bounce","absorbing","moved","cool","dark"]:
        lab.call("set_scenario",name)
        for k in range(10): await process_frame
        lighting.call("request_readback")
        var actual: Dictionary={}
        for k in range(120):
            await process_frame
            actual=lighting.call("readback")
            if not actual.is_empty(): break
        if actual.is_empty():
            _fail("Missing GPU readback: "+name)
            return
        var e: PackedFloat32Array=actual["irradiance"]
        var expected: Array=reference["scenarios"][name]["irradiance"]
        var maximum: float=0.0
        var error: float=0.0
        var norm: float=0.0
        if e.size()!=n*4:
            _fail("Incorrect node code texture dimensions")
            return
        for i in range(n):
            for c in range(3):
                if not is_finite(e[i*4+c]) or e[i*4+c]<0:
                    _fail("Invalid energy in GPU capture node")
                    return
                var delta: float=absf(e[i*4+c]-float(expected[i][c]))
                maximum=maxf(maximum,delta)
                error+=delta
                norm+=absf(float(expected[i][c]))
        var relative: float=error/maxf(norm,.00000001)
        if maximum>.003 or relative>.0001:
            _fail("Captured triangle visibility/transport differs from float64: "+name+" max="+str(maximum)+" rel="+str(relative))
            return
        var frame: Image=get_root().get_texture().get_image()
        frames[name]=frame
        _save(frame,"lie12-"+name+".png")
        cases[name]={"maximum_irradiance_error":maximum,"relative_l1_error":relative}
        device=str(actual["device"])
        if name=="bounce":
            lighting.enabled=false
            lighting.call("diagnostic_reference_codes",expected)
            for k in range(8): await process_frame
            var oracle: Image=get_root().get_texture().get_image()
            var pixels: float=_difference(frame,oracle)
            _save(oracle,"lie12-reference-bounce.png")
            if pixels>.002:
                _fail("Captured visible result differs from independent node codes: "+str(pixels))
                return
            cases[name]["rendered_reference_mean_rgb_error"]=pixels
            lighting.enabled=true
    for name in ["bounce","absorbing","moved","cool","dark"]:
        if _difference(frames["direct"],frames[name])<.00001:
            _fail("Capture lighting did not visibly change: "+name)
            return
    var floor_red_drop: float=0.0
    var floor_green_drop: float=0.0
    for i in range(n):
        if "neutral receiver floor" in str(model["patches"][i]["material"]):
            floor_red_drop+=float(reference["scenarios"]["bounce"]["total_flux"][i][0])-float(reference["scenarios"]["absorbing"]["total_flux"][i][0])
            floor_green_drop+=float(reference["scenarios"]["bounce"]["total_flux"][i][1])-float(reference["scenarios"]["absorbing"]["total_flux"][i][1])
    if floor_red_drop<=.00001 or floor_red_drop<=floor_green_drop*2:
        _fail("Red captured material did not contribute red secondary power to neutral captured floor")
        return
    lab.call("set_scenario","bounce")
    for k in range(10): await process_frame
    var near_frame: Image=get_root().get_texture().get_image()
    if _foreground(near_frame)<300:
        _fail("Capture disappeared from viewport")
        return
    lab.set("distance_scale",1.5)
    for k in range(10): await process_frame
    var far_frame: Image=get_root().get_texture().get_image()
    _save(far_frame,"lie12-far.png")
    var ratio: float=float(_foreground(far_frame))/float(_foreground(near_frame))
    if ratio<.2 or ratio>.7:
        _fail("Captured XYZ geometry did not change perceived size: "+str(ratio))
        return
    lab.set("distance_scale",1.0)
    lab.set("yaw_degrees",35.0)
    for k in range(12): await process_frame
    _save(get_root().get_texture().get_image(),"lie12-orbit-35.png")
    if _difference(near_frame,get_root().get_texture().get_image())<.003:
        _fail("Captured surfaces did not change camera angle")
        return
    lab.set("yaw_degrees",0.0)
    for k in range(10): await process_frame
    var tex:=Image.create(16,16,false,Image.FORMAT_RGBA8)
    tex.fill(Color(0,1,0))
    var sprite:=Sprite3D.new()
    sprite.texture=ImageTexture.create_from_image(tex)
    sprite.pixel_size=.1
    sprite.shaded=false
    sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED
    var eye: Vector3=(lab.get("camera") as Camera3D).position
    sprite.position=eye*.4
    lab.add_child(sprite)
    for k in range(8): await process_frame
    var front: Image=get_root().get_texture().get_image()
    var middle: Vector2i=front.get_size()/2
    var green: Color=front.get_pixel(middle.x,middle.y)
    if green.g<green.r+.25 or green.g<green.b+.25:
        _fail("Closer native sprite was overwritten by capture compositor")
        return
    _save(front,"lie12-native-front.png")
    sprite.position=-eye.normalized()*1.5
    for k in range(8): await process_frame
    var rear: Image=get_root().get_texture().get_image()
    _save(rear,"lie12-native-rear.png")
    if _difference(front,rear)<.003:
        _fail("Native/capture depth ordering did not react")
        return
    sprite.queue_free()
    var metadata: Dictionary=effect.get("metadata")
    var report: Dictionary={"experiment":"LIE12-captured-gray-material-node-codes-v1","device":device,
        "backend":"Software Vulkan CI; physical-device performance unmeasured","viewport":[near_frame.get_width(),near_frame.get_height()],
        "visible_source_mesh_nodes":0,"source_capture_samples":65536,"mapped_valid_pixels":metadata["mapped_valid_pixels"],
        "transport_nodes":n,"invisible_triangle_proxy":metadata["triangle_count"],"max_depth_proxy_distance":metadata["max_depth_proxy_distance"],
        "scenarios":cases,"floor_red_power_reduction_at_high_absorption":floor_red_drop,"floor_green_power_reduction":floor_green_drop,
        "perspective_area_ratio_at_1_5x_distance":ratio,"native_front_rear_depth_test":"passed",
        "limitations":"Four 128-square views, 256-square reprojection, constant opaque source material colors, clustered diffuse transport, static geometry visibility cache; no native depth writeback, specular, transmission or mobile FPS claim."}
    var file: FileAccess=FileAccess.open("res://lie12-diagnostic.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  "))
    print("LIE-12 PASS ",JSON.stringify(report))
    lab.queue_free()
    for k in range(6): await process_frame
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

func _foreground(image: Image) -> int:
    var bg: Color=image.get_pixel(0,0)
    var count: int=0
    for y in range(0,image.get_height(),4):
        for x in range(0,image.get_width(),4):
            var c: Color=image.get_pixel(x,y)
            if absf(c.r-bg.r)+absf(c.g-bg.g)+absf(c.b-bg.b)>.08: count+=1
    return count

func _visible_meshes(node: Node) -> int:
    var count: int=1 if node is MeshInstance3D and (node as MeshInstance3D).visible else 0
    for child in node.get_children(): count+=_visible_meshes(child)
    return count

func _save(image: Image,name: String) -> void:
    if image.save_png(ProjectSettings.globalize_path("res://"+name))!=OK: _fail("Cannot save "+name)

func _fail(message: String) -> void:
    failed=true
    printerr("LIE-12 FAIL: ",message)
    quit(1)
