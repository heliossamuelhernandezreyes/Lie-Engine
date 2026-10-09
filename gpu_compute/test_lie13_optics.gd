extends SceneTree
var lab: Node3D
var optics: CompositorEffect
var lighting: CompositorEffect
var report: Dictionary={"experiment":"LIE-13 secondary radius and thin dielectric sprites", "backend":"Software Vulkan CI; hardware/mobile performance unmeasured"}

func _initialize() -> void:
    call_deferred("_run")

func settle(frames: int=5) -> void:
    for k in range(frames): await process_frame

func read(effect: CompositorEffect) -> Dictionary:
    effect.call("request_readback")
    for k in range(120):
        await process_frame
        var value: Dictionary=effect.call("readback")
        if not value.is_empty(): return value
    return {}

func _run() -> void:
    var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://captures/coded_shard/lie13-reference.json"))
    if not parsed is Dictionary: fail("Missing float64 LIE-13 oracle"); return
    var reference: Dictionary=parsed
    lab=load("res://lie13_lab.tscn").instantiate() as Node3D
    get_root().add_child(lab)
    lab.set("link_transmission",false)
    lab.set("animate",false)
    optics=lab.get("optics")
    lighting=lab.get("lighting")
    for k in range(180):
        await process_frame
        if bool(optics.get("gpu_ready")) and int(optics.get("frame_count"))>3: break
    if not bool(optics.get("gpu_ready")): fail("Optical Vulkan pipeline unavailable: "+str(optics.get("failure"))); return
    if visible_meshes(lab)!=0: fail("Visible source meshes entered the sprite lab"); return
    (lab.get("label") as Label).visible=false
    lab.call("set_optical_scene","none")
    var cases: Dictionary={}
    for name in ["direct","bounce","short","legacy","absorbing","dark","filtered"]:
        lab.call("set_scenario",name)
        await settle()
        var actual: Dictionary=await read(lighting)
        if actual.is_empty(): fail("Missing transport readback"); return
        var values: PackedFloat32Array=actual["irradiance"]
        var frontier: PackedFloat32Array=actual["frontier"]
        var expected: Dictionary=reference["scenarios"][name]
        var radii: Array=expected["secondary_radius_by_generation"].back()
        var maximum: float=0
        var radius_error: float=0
        var radius_max: float=0
        var error: float=0
        var norm: float=0
        for i in range(radii.size()):
            radius_error=maxf(radius_error,absf(frontier[i*4+3]-float(radii[i])))
            radius_max=maxf(radius_max,frontier[i*4+3])
            for c in range(3):
                if not is_finite(values[i*4+c]) or values[i*4+c]<0: fail("Invalid GPU power"); return
                var delta: float=absf(values[i*4+c]-float(expected["irradiance"][i][c]))
                maximum=maxf(maximum,delta)
                error+=delta
                norm+=absf(float(expected["irradiance"][i][c]))
        if maximum>.003 or error/maxf(norm,1e-8)>.0001 or radius_error>.0001:
            fail("Radius/sheet GPU mismatch "+name+" E="+str(maximum)+" R="+str(radius_error)); return
        cases[name]={"maximum_irradiance_error":maximum,"maximum_radius_error_m":radius_error,"last_generation_radius_max_m":radius_max}
        save("lie13-radius-"+name+".png")
        report["device"]=actual["device"]
    report["transport"]=cases
    report["energy_by_generation"]=reference["scenarios"]["bounce"]["energy_by_generation"]
    lab.call("set_scenario","bounce")
    lab.call("set_optical_scene","none")
    await settle()
    var baseline: Image=frame()
    lab.call("set_optical_scene","identity")
    await settle()
    var identity: float=difference(baseline,frame())
    if identity>.000001: fail("Index-matched unabsorbing sprite changed image: "+str(identity)); return
    report["identity_image_mean_error"]=identity
    var images: Dictionary={}
    for name in ["glass","thick","water","rain","layers","mixed"]:
        lab.call("set_optical_scene",name)
        await settle()
        images[name]=frame()
        save("lie13-"+name+".png")
        if difference(baseline,images[name])<.000001: fail("Invisible optical scene "+name); return
    lab.call("set_optical_scene","glass")
    await settle()
    var coefficients: Dictionary=await read(optics)
    if coefficients.is_empty(): fail("No dielectric coefficient readback"); return
    var data: PackedFloat32Array=coefficients["coefficients"]
    var size: int=coefficients["size"]
    var index: int=(size/2*size+size/2)*4
    # Normal-incidence glass: exact Fresnel .04; Beer with 25mm RGB filter.
    var expected_t:=Vector3(pow(.96,2)*exp(-3*.025),pow(.96,2)*exp(-.5*.025),pow(.96,2)*exp(-.2*.025))
    if absf(data[index]-.04)>.0001: fail("Incorrect glass Fresnel: "+str(data[index])); return
    for c in range(3):
        if absf(data[index+1+c]-expected_t[c])>.0001: fail("Incorrect GPU Beer transmission"); return
    report["glass_center_fresnel"]=data[index]
    report["glass_center_transmission"]=[data[index+1],data[index+2],data[index+3]]
    lab.call("set_optical_scene","thick")
    optics.set("diagnostic_mode",1)
    await settle()
    var refracted: Dictionary=await read(optics)
    var probe: Dictionary=reference["refraction_probe"]
    var probe_index: int=(int(probe["pixel"][1])*size+int(probe["pixel"][0]))*4
    var probe_data: PackedFloat32Array=refracted["coefficients"]
    var refraction_error: float=absf(probe_data[probe_index+2]-float(probe["cos_transmitted"]))
    for c in range(2): refraction_error=maxf(refraction_error,absf(probe_data[probe_index+c]-float(probe["uv_offset"][c])))
    if refraction_error>.00001 or probe_data[probe_index+3]<.5: fail("GPU refractive displacement differs from Snell slab oracle"); return
    report["refraction_uv_and_cos_max_error"]=refraction_error
    report["refraction_uv_offset"]=[probe_data[probe_index],probe_data[probe_index+1]]
    optics.set("diagnostic_mode",0)
    report["thickness_image_difference"]=difference(images["glass"],images["thick"])
    if float(report["thickness_image_difference"])<.00001: fail("Thickness does not alter glass"); return
    lab.call("set_optical_scene","layers")
    await settle()
    var layers: Array=lab.call("optical_sprites","layers")
    layers.reverse()
    optics.call("set_sprites",layers)
    await settle()
    var order_error: float=difference(images["layers"],frame())
    if order_error>.000001: fail("Transparency depends on submission order: "+str(order_error)); return
    report["layer_submission_order_mean_error"]=order_error
    lab.call("set_optical_scene","water")
    lab.set("optical_time",1.25)
    await settle()
    var wave_change: float=difference(images["water"],frame())
    if wave_change<.00001: fail("Prescribed water normal did not animate"); return
    save("lie13-water-wave.png")
    report["wave_image_difference"]=wave_change
    lab.set("optical_time",0)
    lab.call("set_optical_scene","glass")
    await settle()
    # Optical geometry behind a captured opaque centre must not be visible.
    var camera: Camera3D=lab.get("camera")
    var behind: Array=lab.call("optical_sprites","glass")
    var p: Vector3=-camera.position.normalized()*2
    behind[0]["center"]=[p.x,p.y,p.z]
    optics.call("set_sprites",behind)
    await settle()
    var midpoint: Vector2i=frame().get_size()/2
    var hidden_error: float=color_error(frame().get_pixelv(midpoint),baseline.get_pixelv(midpoint))
    if hidden_error>.003: fail("Behind-capture transparency leaked forward"); return
    save("lie13-glass-behind.png")
    report["behind_capture_center_error"]=hidden_error
    # Native opaque sprites contribute to the same nearest depth field.
    lab.call("set_optical_scene","glass")
    var tex:=Image.create(16,16,false,Image.FORMAT_RGBA8)
    tex.fill(Color(0,1,0))
    var native:=Sprite3D.new()
    native.texture=ImageTexture.create_from_image(tex)
    native.pixel_size=.018
    native.shaded=false
    native.alpha_cut=SpriteBase3D.ALPHA_CUT_DISCARD
    native.billboard=BaseMaterial3D.BILLBOARD_ENABLED
    native.position=camera.position*.4
    lab.add_child(native)
    var guard: Array=lab.call("optical_sprites","water")
    guard[0]["wave"]=.15
    guard[0]["thickness"]=.5
    optics.call("set_sprites",guard)
    optics.set("diagnostic_mode",1)
    await settle()
    var green: Color=frame().get_pixelv(midpoint)
    if green.g<green.r+.25 or green.g<green.b+.25: fail("Glass overwrote nearer native sprite"); return
    save("lie13-native-front.png")
    var guard_data: Dictionary=await read(optics)
    var guard_coefficients: PackedFloat32Array=guard_data["coefficients"]
    var rejected: int=0
    for i in range(guard_coefficients.size()/4):
        if guard_coefficients[i*4+2]>0 and guard_coefficients[i*4+3]<.5: rejected+=1
    if rejected==0: fail("Refraction foreground rejection branch was not exercised"); return
    report["rejected_foreground_refraction_samples"]=rejected
    optics.set("diagnostic_mode",0)
    lab.call("set_optical_scene","glass")
    native.queue_free()
    await settle()
    report["native_opaque_depth_test"]="passed"
    var near_data: Dictionary=await read(optics)
    var near_count: int=coverage(near_data["coefficients"])
    lab.set("distance_scale",1.5)
    await settle()
    var far_data: Dictionary=await read(optics)
    var ratio: float=float(coverage(far_data["coefficients"]))/maxi(near_count,1)
    if ratio<.2 or ratio>.7: fail("Optical XYZ sprite scale did not follow perspective: "+str(ratio)); return
    save("lie13-glass-far.png")
    report["perspective_optical_coverage_at_1_5x_distance"]=ratio
    # Default runtime registers each glass/water material in BOTH consumers.
    # Earlier optical tests isolate camera coefficients from illumination.
    lab.set("distance_scale",1.0)
    lab.set("link_transmission",true)
    lab.call("set_scenario","bounce")
    lab.call("set_optical_scene","mixed")
    var linked_model: Dictionary=lab.get("model")
    linked_model["lights"][0]["position"]=[.1,.65,2.25]
    lighting.call("set_light_codes",linked_model)
    await settle()
    var linked: Dictionary=await read(lighting)
    var linked_values: PackedFloat32Array=linked["irradiance"]
    var linked_expected: Array=reference["scenarios"]["coupled"]["irradiance"]
    var linked_error: float=0.0
    for i in range(linked_expected.size()):
        for c in range(3): linked_error=maxf(linked_error,absf(linked_values[i*4+c]-float(linked_expected[i][c])))
    if linked_error>.003: fail("Shared camera/transport material registration differs from oracle"); return
    report["coupled_glass_water_irradiance_error"]=linked_error
    var transmitted_drop: Array=[0.0,0.0,0.0]
    for i in range(linked_expected.size()):
        for c in range(3): transmitted_drop[c]+=float(reference["scenarios"]["coupled_clear"]["total_flux"][i][c])-float(reference["scenarios"]["coupled"]["total_flux"][i][c])
    if float(transmitted_drop[0])<.00001: fail("Coupled sheets did not filter a crossing primary source"); return
    report["coupled_rgb_power_reduction_by_sheets"]=transmitted_drop
    save("lie13-coupled.png")
    report["visible_source_meshes"]=0
    report["optical_resolution"]=[256,256]
    report["max_optical_layers_per_pixel"]=4
    report["limitations"]="Thin sheets with first internal return; approximate screen-space slab displacement, explicit environment/punctual reflection, straight-segment transmitted shadows, four nearest layers, prescribed waves and deterministic rain sprites. No caustics, full glass mesh capture, volume-fluid simulation or native depth writeback."
    var file: FileAccess=FileAccess.open("res://lie13-diagnostic.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  "))
    print("LIE-13 PASS ",JSON.stringify(report))
    lab.queue_free()
    await settle()
    quit(0)

func coverage(data: PackedFloat32Array) -> int:
    var count: int=0
    for i in range(data.size()/4):
        if data[i*4]>=0: count+=1
    return count

func frame() -> Image:
    return get_root().get_texture().get_image()

func save(name: String) -> void:
    if frame().save_png(ProjectSettings.globalize_path("res://"+name))!=OK: fail("Image save failed")

func color_error(a: Color,b: Color) -> float:
    return absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)

func difference(a: Image,b: Image) -> float:
    var value: float=0
    var count: int=0
    for y in range(0,a.get_height(),4):
        for x in range(0,a.get_width(),4):
            value+=color_error(a.get_pixel(x,y),b.get_pixel(x,y))
            count+=3
    return value/maxi(count,1)

func visible_meshes(node: Node) -> int:
    var count: int=1 if node is MeshInstance3D and (node as MeshInstance3D).visible else 0
    for child in node.get_children(): count+=visible_meshes(child)
    return count

func fail(message: String) -> void:
    printerr("LIE-13 FAIL: ",message)
    var img: Image=frame()
    if img!=null: img.save_png(ProjectSettings.globalize_path("res://lie13-failure.png"))
    quit(1)
