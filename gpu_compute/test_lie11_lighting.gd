extends SceneTree
## Acceptance: real GPU power vs independent float64, real grayscale-sprite frames.
var failed: bool=false

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/lie11-reference.json"))
    if not parsed is Dictionary:
        _fail("Generate the independent Python reference before Vulkan acceptance")
        return
    var reference: Dictionary=parsed
    var lab: Node3D=load("res://lie11_lab.tscn").instantiate() as Node3D
    get_root().add_child(lab)
    for k in range(120):
        await process_frame
        if bool(lab.get("ready_for_capture")): break
    if not bool(lab.get("ready_for_capture")):
        _fail("Light codes were not published to grayscale sprites")
        return
    var effect: CompositorEffect=lab.get("effect")
    var sprites: Array=lab.get("sprites")
    if sprites.size()!=64 or _visible_source_meshes(lab)!=0:
        _fail("Expected 64 grayscale sprites and zero visible source mesh nodes")
        return
    var gray: Image=(lab.get("gray_texture") as ImageTexture).get_image()
    for y in range(0,gray.get_height(),8):
        for x in range(0,gray.get_width(),8):
            var c: Color=gray.get_pixel(x,y)
            if absf(c.r-c.g)>0.00001 or absf(c.r-c.b)>0.00001:
                _fail("Source sprite contains baked RGB lighting")
                return
    (lab.get("label") as Label).visible=false
    var cases: Dictionary={}
    var frames: Dictionary={}
    var device: String=""
    var bytes: int=0
    for name in ["direct","bounce","absorbing","blocked","moved","cool"]:
        lab.call("set_scenario",name)
        for k in range(10): await process_frame
        effect.call("request_readback")
        var data: Dictionary={}
        for k in range(90):
            await process_frame
            data=effect.call("readback")
            if not data.is_empty(): break
        if data.is_empty():
            _fail("No GPU diagnostic readback for "+name)
            return
        var actual: PackedFloat32Array=data["irradiance"]
        var actual_flux: PackedFloat32Array=data["flux"]
        var expected: Array=reference["scenarios"][name]["irradiance"]
        var expected_flux: Array=reference["scenarios"][name]["total_flux"]
        if actual.size()!=64*4 or actual_flux.size()!=64*4:
            _fail("Malformed GPU code texture or flux buffer")
            return
        var maximum: float=0.0
        var error: float=0.0
        var denominator: float=0.0
        for i in range(64):
            for c in range(3):
                var a: float=actual[i*4+c]
                var target: float=float(expected[i][c])
                if not is_finite(a) or a<0.0:
                    _fail("Non-finite or negative GPU light power")
                    return
                maximum=maxf(maximum,absf(a-target))
                error+=absf(a-target)
                denominator+=absf(target)
                if absf(actual_flux[i*4+c]-float(expected_flux[i][c]))>0.002:
                    _fail("GPU power differs from the independent radiometric reference")
                    return
        var relative: float=error/maxf(denominator,0.00000001)
        if maximum>0.003 or relative>0.0001:
            _fail("GPU/reference irradiance mismatch: "+name+" max="+str(maximum)+" relative="+str(relative))
            return
        var image: Image=get_root().get_texture().get_image()
        _save(image,"lie11-"+name+".png")
        frames[name]=image
        cases[name]={"gpu_reference_max_absolute_error":maximum,"gpu_reference_relative_l1_error":relative}
        device=str(data["device"])
        bytes=int(data["allocation_bytes"])
        if name=="bounce":
            # Same sprites, camera, material shader and display mapping. Only
            # substitute independent float64 irradiance for the GPU code texture.
            var values:=PackedFloat32Array()
            for row in expected:
                values.append_array(PackedFloat32Array([float(row[0]),float(row[1]),float(row[2]),1.0]))
            var cpu_image:=Image.create_from_data(64,1,false,Image.FORMAT_RGBAF,values.to_byte_array())
            var cpu_texture:=ImageTexture.create_from_image(cpu_image)
            effect.enabled=false
            lab.call("set_code_texture",cpu_texture)
            for k in range(8): await process_frame
            var cpu_frame: Image=get_root().get_texture().get_image()
            _save(cpu_frame,"lie11-reference-bounce.png")
            var pixel_error: float=_difference(image,cpu_frame)
            if pixel_error>0.005:
                _fail("Visible GPU sprites differ from independently lit reference: "+str(pixel_error))
                return
            cases[name]["visible_reference_mean_rgb_error"]=pixel_error
            lab.call("set_code_texture",lab.get("light_texture"))
            effect.enabled=true
    for name in ["bounce","absorbing","blocked","moved","cool"]:
        if _difference(frames["direct"],frames[name])<0.001:
            _fail("Scenario did not visibly change the grayscale sprites: "+name)
            return
    lab.call("set_scenario","bounce")
    for k in range(10): await process_frame
    var near_image: Image=get_root().get_texture().get_image()
    var near_pixels: int=_foreground(near_image)
    if near_pixels<1000:
        _fail("Grayscale sprite surfaces are missing")
        return
    lab.set("distance_scale",1.5)
    for k in range(10): await process_frame
    var far_image: Image=get_root().get_texture().get_image()
    _save(far_image,"lie11-far.png")
    var scale_ratio: float=float(_foreground(far_image))/float(near_pixels)
    if scale_ratio<0.2 or scale_ratio>0.7:
        _fail("XYZ perspective did not reduce perceived size: "+str(scale_ratio))
        return
    lab.set("distance_scale",1.0)
    lab.set("yaw_degrees",35.0)
    for k in range(10): await process_frame
    var orbit: Image=get_root().get_texture().get_image()
    _save(orbit,"lie11-orbit-35.png")
    if _difference(near_image,orbit)<0.005:
        _fail("Camera rotation did not change the spatial sprite view")
        return
    lab.set("yaw_degrees",0.0)
    lab.call("set_scenario","direct")
    for k in range(15): await process_frame
    var direct_timing: Dictionary=await _timing(120)
    lab.call("set_scenario","bounce")
    for k in range(15): await process_frame
    var bounce_timing: Dictionary=await _timing(120)
    var report: Dictionary={"experiment":"LIE11-coded-gray-sprites-v1","device":device,
        "backend":"GitHub CI Vulkan software; not mobile hardware",
        "visible_source_mesh_nodes":0,"grayscale_sprite_nodes":64,
        "viewport":[near_image.get_width(),near_image.get_height()],"lighting_owned_gpu_allocation_bytes":bytes,
        "max_bounces":2,"scenarios":cases,"perspective_area_ratio_at_1_5x_distance":scale_ratio,
        "two_bounce_relative_l1_error_vs_infinite_same_graph":reference["two_bounce_relative_l1_error_vs_infinite"],
        "frame_pacing_direct_ms":direct_timing,"frame_pacing_two_bounces_ms":bounce_timing,
        "limitations":"Finite planar patches, center quadrature, diffuse RGB only; timings include entire process scheduling on software Vulkan. No physical GPU speedup or full GI accuracy claimed."}
    var file: FileAccess=FileAccess.open("res://lie11-diagnostic.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  "))
    file.close()
    print("LIE-11 PASS ",JSON.stringify(report))
    lab.queue_free()
    for k in range(6): await process_frame
    quit(0)

func _visible_source_meshes(node: Node) -> int:
    var count: int=1 if node is MeshInstance3D and (node as MeshInstance3D).visible else 0
    for child in node.get_children(): count+=_visible_source_meshes(child)
    return count

func _difference(a: Image,b: Image) -> float:
    var value: float=0.0
    var count: int=0
    for y in range(0,a.get_height(),8):
        for x in range(0,a.get_width(),8):
            var ca: Color=a.get_pixel(x,y)
            var cb: Color=b.get_pixel(x,y)
            value+=absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)
            count+=3
    return value/float(maxi(count,1))

func _foreground(image: Image) -> int:
    var background: Color=image.get_pixel(0,image.get_height()-1)
    var count: int=0
    for y in range(0,image.get_height(),2):
        for x in range(0,image.get_width(),2):
            var c: Color=image.get_pixel(x,y)
            if absf(c.r-background.r)+absf(c.g-background.g)+absf(c.b-background.b)>0.1: count+=1
    return count

func _timing(n: int) -> Dictionary:
    var values: Array[float]=[]
    var last: int=Time.get_ticks_usec()
    for k in range(n):
        await process_frame
        var now: int=Time.get_ticks_usec()
        values.append(float(now-last)/1000.0)
        last=now
    values.sort()
    return {"samples":n,"p50":values[ceili(0.5*n)-1],"p95":values[ceili(0.95*n)-1],"p99":values[ceili(0.99*n)-1]}

func _save(image: Image,path: String) -> void:
    if image.save_png(ProjectSettings.globalize_path("res://"+path))!=OK: _fail("Cannot save "+path)

func _fail(message: String) -> void:
    failed=true
    printerr("LIE-11 FAIL: ",message)
    quit(1)
