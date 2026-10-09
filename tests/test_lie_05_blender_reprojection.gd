extends SceneTree
## Actual Blender-derived 0° and 90° captured views are reprojected to
## an unseen 45° perspective-camera position. Capture frames are GPU rendered.
const Lab = preload("res://scenes/lie_reprojection_lab.tscn")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var scene: Node3D = Lab.instantiate()
    root.add_child(scene)
    scene.set_process(false)
    var node: Node3D = scene.get_node("LieNovelView")
    node.set_process(false)
    var camera: Camera3D = scene.get_node("LieCamera")
    node.set("azimuth_steps", 4)
    node.set("elevations", PackedFloat32Array([-30, 0, 30]))
    node.set("target_resolution", 128)
    node.set("source_stride", 1)
    node.set("crop_screen_pixels", 320.0)
    for child in scene.get_children():
        if child is CanvasLayer:
            child.visible = false

    var coverages := []
    var hashes := []
    var angle_codes := []
    for degrees in [0.0, 45.0, 90.0]:
        var radians: float = deg_to_rad(degrees)
        camera.position = Vector3(6.0 * sin(radians), 1.2, 6.0 * cos(radians))
        camera.look_at(Vector3.ZERO, Vector3.UP)
        if not bool(node.call("rebuild")):
            _fail("No depth-reprojected mesh at %s degrees" % str(degrees))
            return
        if not bool(node.get("using_real_capture")):
            _fail("Blender captures were not imported")
            return
        var count: int = int(node.get("triangles"))
        var covered: int = int(node.get("coverage"))
        if count < 20 or covered < 30:
            _fail("Reprojection lacks useful reconstructed geometry")
            return
        coverages.append(covered)
        angle_codes.append(str(node.get("last_code")))
        for frame in range(10):
            await process_frame
        var frame_image: Image = root.get_texture().get_image()
        if frame_image.is_empty():
            _fail("Could not read rendered viewport")
            return
        var output_file: String = "res://lie-05-angle-%d.png" % int(degrees)
        if frame_image.save_png(output_file) != OK:
            _fail("Failed to store native Godot viewport image")
            return
        hashes.append(FileAccess.get_sha256(output_file))
    if hashes[0] == hashes[1] or hashes[1] == hashes[2]:
        _fail("Camera movement did not affect reprojected rendered view")
        return
    # Preserve same-camera original source geometry for visual review at
    # exactly 45°; never include source mesh during Lie rendering.
    var ref_resource: PackedScene = load(
        "res://assets/captures/demo_shard/source.glb") as PackedScene
    if ref_resource == null:
        _fail("Reference GLB is not imported")
        return
    var reference: Node3D = ref_resource.instantiate() as Node3D
    reference.name = "GroundTruthSourceMesh"
    scene.add_child(reference)
    node.visible = false
    var halfway: float = deg_to_rad(45.0)
    camera.position = Vector3(6.0 * sin(halfway), 1.2, 6.0 * cos(halfway))
    camera.look_at(Vector3.ZERO, Vector3.UP)
    for frame in range(12):
        await process_frame
    var reference_frame: Image = root.get_texture().get_image()
    if reference_frame.is_empty() or reference_frame.save_png(
            "res://lie-05-reference-3d-45.png") != OK:
        _fail("Could not preserve matched-camera original GLB reference")
        return
    reference.visible = false
    node.visible = true
    print("LIE-05 BLENDER NOVEL VIEW PASS angles=[0,45,90] coverage=%s codes=%s" %
        [str(coverages), str(angle_codes)])
    quit(0)

func _fail(reason: String) -> void:
    printerr("LIE-05 NOVEL VIEW FAIL ", reason)
    quit(1)
