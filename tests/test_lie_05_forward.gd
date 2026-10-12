extends SceneTree
const Forward = preload("res://scripts/lie_forward_reprojector.gd")
const Mesher = preload("res://scripts/lie_depth_mesher.gd")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var camera := Camera3D.new()
    camera.name = "LieReprojectionTestCamera"
    camera.current = true
    camera.fov = 50
    camera.position = Vector3(3.8, 1.1, 3.8)
    root.add_child(camera)
    camera.look_at(Vector3.ZERO, Vector3.UP)

    var capture: Dictionary = Mesher.default_capture()
    var color_image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
    var depth_image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
    color_image.fill(Color(0.75, 0.45, 0.2, 1.0))
    depth_image.fill(Color(0.5, 0.5, 0.5, 1.0))
    var data := []
    for az in [0, 1]:
        data.append({"albedo": color_image, "depth": depth_image,
            "azimuth": az, "elevation": 0.0, "weight": 0.5})
    var result: Dictionary = Forward.reconstruct(data, camera,
        Transform3D.IDENTITY, capture, 4, 128, 400.0, 1)
    if result["mesh"] == null or int(result["triangles"]) < 50:
        _fail("No two-view reprojected geometry")
        return
    if int(result["coverage"]) < 50 or result["source_hits"].size() != 2:
        _fail("Target-camera depth bin coverage missing")
        return
    if int(result["source_hits"][0]) < 1 or int(result["source_hits"][1]) < 1:
        _fail("Both sources must contribute to novel-view reconstruction")
        return
    var rendered_mesh: ArrayMesh = result["mesh"]
    var arrays: Array = rendered_mesh.surface_get_arrays(0)
    if arrays[Mesh.ARRAY_COLOR] is not PackedColorArray or arrays[Mesh.ARRAY_VERTEX] is not PackedVector3Array:
        _fail("Z-buffer-reconstructable vertices/colors missing")
        return

    # Two captures at the same angle, but one surface is closer in 3D.
    # Blue background MUST NOT simply be blended with red foreground.
    var near_depth := Image.create(32, 32, false, Image.FORMAT_RGBA8)
    var far_depth := Image.create(32, 32, false, Image.FORMAT_RGBA8)
    var red := Image.create(32, 32, false, Image.FORMAT_RGBA8)
    var blue := Image.create(32, 32, false, Image.FORMAT_RGBA8)
    near_depth.fill(Color(0.25, 0.25, 0.25, 1))
    far_depth.fill(Color(0.85, 0.85, 0.85, 1))
    red.fill(Color(1, 0, 0, 1))
    blue.fill(Color(0, 0, 1, 1))
    var z_test: Dictionary = Forward.reconstruct([
        {"albedo": blue, "depth": far_depth, "azimuth": 0, "elevation": 0.0, "weight": 0.5},
        {"albedo": red, "depth": near_depth, "azimuth": 0, "elevation": 0.0, "weight": 0.5}
    ], camera, Transform3D.IDENTITY, capture, 4, 128, 400.0, 1)
    if z_test["mesh"] == null:
        _fail("Z fusion produced no geometry")
        return
    var positions: PackedVector3Array = z_test["mesh"].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
    var colors: PackedColorArray = z_test["mesh"].surface_get_arrays(0)[Mesh.ARRAY_COLOR]
    var nr := 0
    var nb := 0
    for i in range(colors.size()):
        var c: Color = colors[i]
        if c.a < 0.5:
            continue
        if c.r > c.b * 3:
            nr += 1
        elif c.b > c.r * 3:
            nb += 1
    if nr < 20 or nr <= nb:
        _fail("Near red surface was not favored over distant blue")
        return
    if positions.size() != colors.size():
        _fail("Vertex-color fusion lost 3D position correspondence")
        return
    print("LIE-05 WARP PASS two_sources=true merged_depth=true triangles=%d coverage=%d" %
        [int(result["triangles"]), int(result["coverage"])])
    quit(0)

func _fail(reason: String) -> void:
    printerr("LIE-05 WARP FAIL ", reason)
    quit(1)
