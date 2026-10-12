extends SceneTree
## LIE-10 honest matched-viewport visual quality and frame-pacing diagnostic.
## GPU composition of 4 actual 128x128 Blender views vs same source GLB.
## FRAME PACING includes OS + Godot + software Vulkan: NOT GPU timestamps.
func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var lab: Node3D = load("res://lie10_lab.tscn").instantiate() as Node3D
    if lab==null:
        _fail("Cannot instantiate LIE10 GPU comparison scene")
        return
    get_root().add_child(lab)
    var effect: CompositorEffect = lab.get("effect")
    if not bool(effect.get("capture_loaded")) or int(effect.get("captured_valid_pixels"))<1000:
        _fail("Missing real Blender complex fixture captures")
        return
    for k in range(18):
        await process_frame
    if not bool(effect.get("gpu_ready")) or int(effect.get("frame_count"))<2:
        _fail("GPU reprojection did not execute")
        return
    var warm: Image=get_root().get_texture().get_image()
    var bg: Color=warm.get_pixel(8,8)
    if _foreground_count(warm,bg)<150:
        _fail("Complex Lie object is not present in the rendered viewport")
        return
    _save(warm,"lie10-warm-0.png")

    effect.call("set_light_mode",1)
    for k in range(12):
        await process_frame
    var cool: Image=get_root().get_texture().get_image()
    var light_difference: float=_difference(warm,cool)
    _save(cool,"lie10-cool-0.png")
    if light_difference<8.0:
        _fail("Real captured normals did not respond to warm/cool GPU lights: "+str(light_difference))
        return

    effect.call("set_light_mode",0)
    lab.set("yaw_degrees",35.0)
    lab.call("_move_camera")
    for k in range(16):
        await process_frame
    var orbit: Image=get_root().get_texture().get_image()
    _save(orbit,"lie10-lie-35.png")
    if _difference(warm,orbit)<8.0:
        _fail("Geometry did not react to camera yaw")
        return

    var packed: PackedScene=load("res://captures/complex_shard/source.glb") as PackedScene
    if packed==null:
        _fail("Missing original GLB for fair rasterized reference")
        return
    var source: Node3D=packed.instantiate() as Node3D
    if source==null:
        _fail("Could not instantiate GLB scene")
        return
    lab.add_child(source)
    var manifest: Variant=JSON.parse_string(FileAccess.get_file_as_string(
        "res://captures/complex_shard/manifest.json"))
    if not manifest is Dictionary:
        _fail("Missing capture camera origin")
        return
    var center: Array=manifest.get("center_blender",[])
    if center.size()!=3:
        _fail("Invalid Blender center metadata")
        return
    # Coordinate conversion Blender Z-up -> Godot Y-up.
    source.position=Vector3(-float(center[0]),-float(center[2]),float(center[1]))
    var tri_count: int=_triangles(source)
    if tri_count<2500:
        _fail("Reference GLB not sufficiently complex: %d triangles"%tri_count)
        return

    var light:=DirectionalLight3D.new()
    light.rotation_degrees=Vector3(-40,35,0)
    light.light_energy=1.8
    lab.add_child(light)
    effect.enabled=false
    for k in range(16):
        await process_frame
    var native35: Image=get_root().get_texture().get_image()
    _save(native35,"lie10-glb-35.png")
    var iou35: float=_silhouette_iou(orbit,native35,bg)
    if iou35<=0.02:
        _fail("GPU Lie and native GLB have no meaningful silhouette overlap at 35deg: "+str(iou35))
        return
    lab.set("yaw_degrees",0.0)
    lab.call("_move_camera")
    for k in range(15):
        await process_frame
    var native0: Image=get_root().get_texture().get_image()
    _save(native0,"lie10-glb-0.png")
    var iou0: float=_silhouette_iou(warm,native0,bg)
    if iou0<=0.02:
        _fail("Lie silhouette failed to align with original GLB at 0deg: "+str(iou0))
        return
    # Timings deliberately exclude screenshot readbacks and use the SAME viewport.
    var raster_timing: Dictionary=await _frame_diagnostics(30)
    source.visible=false
    effect.enabled=true
    for k in range(10):
        await process_frame
    var lie_timing: Dictionary=await _frame_diagnostics(30)
    source.visible=true
    effect.enabled=false

    var report: Dictionary={
        "experiment":"LIE10-v1",
        "backend":"CI Vulkan software (Lavapipe); NOT mobile GPU",
        "source":"Blender generated 3-channel multi-view glTF capture",
        "native_triangles":tri_count,
        "lie_source_samples":4*128*128,
        "screen_resolution":[warm.get_width(),warm.get_height()],
        "new_camera_angles":[0,35],
        "silhouette_iou_0":iou0,
        "silhouette_iou_35":iou35,
        "light_pixel_difference":light_difference,
        "raster_frame_pacing_ms":raster_timing,
        "lie_frame_pacing_ms":lie_timing,
        "limitations":"Wall-clock process_frame spacing includes scheduling; NOT isolated GPU time or real Android FPS; illumination models differ."
    }
    var file: FileAccess=FileAccess.open("res://lie10-diagnostic.json",FileAccess.WRITE)
    if file==null:
        _fail("Could not write machine-readable benchmark report")
        return
    file.store_string(JSON.stringify(report,"  "))
    file.close()
    print("LIE-10 QUALITY BENCH ",JSON.stringify(report))
    lab.queue_free()
    for k in range(4):
        await process_frame
    quit(0)

func _frame_diagnostics(n: int) -> Dictionary:
    var samples: Array[float]=[]
    var last: int=Time.get_ticks_usec()
    for i in range(n):
        await process_frame
        var now: int=Time.get_ticks_usec()
        samples.append(float(now-last)/1000.0)
        last=now
    samples.sort()
    return {"p50":_percentile(samples,0.50),"p95":_percentile(samples,0.95),
        "p99":_percentile(samples,0.99),"frames":n}

func _percentile(sorted_samples: Array[float],fraction: float)->float:
    return sorted_samples[clampi(int(ceil(fraction*float(sorted_samples.size())))-1,0,sorted_samples.size()-1)]

func _triangles(node: Node)->int:
    var count:=0
    if node is MeshInstance3D:
        var m: Mesh=(node as MeshInstance3D).mesh
        if m!=null:
            for s in range(m.get_surface_count()):
                var a: Array=m.surface_get_arrays(s)
                var indices: PackedInt32Array=a[Mesh.ARRAY_INDEX]
                if not indices.is_empty():
                    count += indices.size()/3
                else:
                    count += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()/3
    for child in node.get_children():
        count += _triangles(child)
    return count

func _save(im: Image, path: String)->void:
    if im.save_png(ProjectSettings.globalize_path("res://"+path))!=OK:
        printerr("LIE10 EVIDENCE SAVE FAILURE ",path)
        quit(1)

func _mask(c: Color,bg: Color)->bool:
    return absf(c.r-bg.r)+absf(c.g-bg.g)+absf(c.b-bg.b)>0.16

func _foreground_count(im: Image,bg: Color)->int:
    var n:=0
    for y in range(16,im.get_height()-16,3):
        for x in range(16,im.get_width()-16,3):
            if _mask(im.get_pixel(x,y),bg):
                n+=1
    return n

func _silhouette_iou(a: Image,b: Image,bg: Color)->float:
    var intersection:=0
    var total:=0
    for y in range(16,a.get_height()-16,2):
        for x in range(16,a.get_width()-16,2):
            var am: bool=_mask(a.get_pixel(x,y),bg)
            var bm: bool=_mask(b.get_pixel(x,y),bg)
            if am or bm:
                total+=1
                if am and bm:
                    intersection+=1
    return float(intersection)/float(maxi(total,1))

func _difference(a: Image,b: Image)->float:
    var error:=0.0
    for y in range(40,a.get_height()-40,3):
        for x in range(40,a.get_width()-40,3):
            var c: Color=a.get_pixel(x,y)
            var d: Color=b.get_pixel(x,y)
            error+=absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)
    return error

func _fail(message: String)->void:
    printerr("LIE-10 FAIL ",message)
    quit(1)
