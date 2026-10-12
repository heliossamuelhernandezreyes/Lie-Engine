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
    var build_times_ms := []
    var midpoint_hits := []
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
        build_times_ms.append(float(node.get("last_build_time_usec")) / 1000.0)
        if absf(degrees - 45.0) < 0.1:
            midpoint_hits = node.get("last_source_hits")
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
    # Captured Lie coordinates are relative to the Blender orbit/bounds
    # center. Move the original GLB by its mapped center for a fair comparison.
    var json_text: String = FileAccess.get_file_as_string(
        "res://assets/captures/demo_shard/manifest.json")
    var manifest: Variant = JSON.parse_string(json_text)
    if not manifest is Dictionary or not manifest.has("center_blender"):
        _fail("Missing capture center required for matched reference alignment")
        return
    var center: Array = manifest["center_blender"]
    reference.position = -Vector3(float(center[0]), float(center[2]), -float(center[1]))
    # Imported glTF uses PBR, while Lie RGB captures are intentionally unlit.
    # Supply explicit light to avoid a nearly-black, invalid ground truth.
    var reference_light := DirectionalLight3D.new()
    reference_light.name = "OriginalGLBReferenceLight"
    reference_light.light_energy = 3.0
    reference_light.rotation_degrees = Vector3(-45, -35, 0)
    scene.add_child(reference_light)
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
    # Approximate foreground-mask overlap with the native source model.
    # It is a diagnostic score, not a photometric or perceptual quality test.
    var lie_frame: Image = Image.load_from_file("res://lie-05-angle-45.png")
    var shared: int = 0
    var either: int = 0
    var missed: int = 0
    var overflow: int = 0
    var background := Color("#0a1726")
    var cx: int = reference_frame.get_width() / 2
    var cy: int = reference_frame.get_height() / 2
    for y in range(cy - 185, cy + 185, 2):
        for x in range(cx - 185, cx + 185, 2):
            var a: Color = lie_frame.get_pixel(x, y)
            var b: Color = reference_frame.get_pixel(x, y)
            var in_lie: bool = (absf(a.r - background.r) + absf(a.g - background.g)
                + absf(a.b - background.b)) > 0.35
            var in_source: bool = (absf(b.r - background.r) + absf(b.g - background.g)
                + absf(b.b - background.b)) > 0.35
            if in_lie or in_source:
                either += 1
            if in_lie and in_source:
                shared += 1
            if in_source and not in_lie:
                missed += 1
            if in_lie and not in_source:
                overflow += 1
    if shared + missed < 20:
        _fail("Invalid or black original GLB reference: fewer than 20 visible foreground samples")
        return
    var approx_iou: float = float(shared) / float(maxi(either, 1))
    print("LIE-05 SAME-CAMERA SILHOUETTE DIAGNOSTIC overlap=%.3f missed=%d extra=%d (threshold-based, not PSNR)" %
        [approx_iou, missed, overflow])
    reference.visible = false
    node.visible = true
    if midpoint_hits.size() != 2 or int(midpoint_hits[0]) < 1 or int(midpoint_hits[1]) < 1:
        _fail("45-degree unseen viewpoint did not fuse TWO original captured view sources")
        return
    print("LIE-05 BLENDER NOVEL VIEW PASS angles=[0,45,90] coverage=%s codes=%s midpoint_hits=%s cpu_ms=%s" %
        [str(coverages), str(angle_codes), str(midpoint_hits), str(build_times_ms)])
    quit(0)

func _fail(reason: String) -> void:
    printerr("LIE-05 NOVEL VIEW FAIL ", reason)
    quit(1)
