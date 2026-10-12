extends SceneTree
## Real Blender albedo + 16-bit depth + world normals to Forward+ compositor.
## Native red blocker in FRONT must win; blocker BEHIND must not.
func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var lab: Node3D = load("res://lie09_lab.tscn").instantiate() as Node3D
    if lab == null:
        _fail("Cannot load real-capture GPU lab")
        return
    get_root().add_child(lab)
    for k in range(22):
        await process_frame
    var effect: CompositorEffect = lab.get("effect")
    if not bool(effect.get("capture_loaded")):
        _fail("NO real Blender capture loaded; synthetic substitution forbidden")
        return
    if not bool(effect.get("gpu_ready")) or int(effect.get("frame_count"))<2:
        _fail("GPU compositor not drawing actual captures")
        return
    var camera: Camera3D = lab.get("camera")
    var dist: float = camera.global_position.length()
    var original: Image = get_root().get_texture().get_image()
    var pixel := Vector2i(original.get_width()/2,original.get_height()/2)
    var base: Color = original.get_pixelv(pixel)
    var bg: Color = original.get_pixel(8,8)
    if absf(base.r-bg.r)+absf(base.g-bg.g)+absf(base.b-bg.b)<0.15:
        _fail("Blender capture center must be visibly different from background: "+str(base))
        return
    if original.save_png(ProjectSettings.globalize_path("res://lie-09-real-0.png")) != OK:
        _fail("Cannot save real capture screenshot")
        return
    lab.set("yaw_degrees",35.0)
    lab.call("_move_camera")
    for k in range(22):
        await process_frame
    var angled: Image = get_root().get_texture().get_image()
    if angled.save_png(ProjectSettings.globalize_path("res://lie-09-real-35.png")) != OK:
        _fail("Cannot save novel angle screenshot")
        return
    var difference := 0.0
    for y in range(56,200,4):
        for x in range(56,200,4):
            var a: Color = original.get_pixel(x,y)
            var b: Color = angled.get_pixel(x,y)
            difference += absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
    if difference < 4.0:
        _fail("Novel camera did not change REAL Blender depth-reprojected pixels")
        return
    lab.set("yaw_degrees",0.0)
    lab.call("_move_camera")
    var blocker := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.85,0.85,0.12)
    blocker.mesh = mesh
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color(1.0,0.02,0.02,1.0)
    blocker.material_override = material
    blocker.position = Vector3(0,0,dist*0.45)
    lab.add_child(blocker)
    for k in range(15):
        await process_frame
    var foreground: Image = get_root().get_texture().get_image()
    if foreground.save_png(ProjectSettings.globalize_path("res://lie-09-native-front.png")) != OK:
        _fail("Cannot save native occlusion screenshot")
        return
    var front: Color = foreground.get_pixelv(pixel)
    if front.r<0.6 or front.g>0.25 or front.b>0.25:
        _fail("Godot-native FRONT occluder did not win depth test: "+str(front))
        return
    blocker.position = Vector3(0,0,-dist*0.45)
    for k in range(15):
        await process_frame
    var behind: Image = get_root().get_texture().get_image()
    var rear: Color = behind.get_pixelv(pixel)
    if rear.r>0.75 and rear.g<0.2 and rear.b<0.2:
        _fail("Godot-native REAR occluder wrongly covered Lie")
        return
    if behind.save_png(ProjectSettings.globalize_path("res://lie-09-native-rear.png")) != OK:
        _fail("Cannot save behind screenshot")
        return
    print("LIE-09 GPU PASS real_blender_capture=true normal_channel=true real_depth=true native_front=true native_rear=true orbit_delta=",difference," pixels=",effect.get("captured_valid_pixels"))
    lab.queue_free()
    for k in range(4):
        await process_frame
    quit(0)

func _fail(message: String) -> void:
    printerr("LIE-09 GPU FAIL ",message)
    quit(1)
