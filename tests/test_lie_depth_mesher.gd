extends SceneTree
const Mesher = preload("res://scripts/lie_depth_mesher.gd")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var meta: Dictionary = {"schema_version": 2, "projection": "orthographic",
        "radius": 1.0, "orthographic_scale": 3.0,
        "linear_depth_meters": {"near": 3.2, "far": 5.8}}
    var capture: Dictionary = Mesher.capture_from_manifest(meta)
    if capture.is_empty():
        _fail("Valid manifest rejected")
        return
    var center_front: Vector3 = Mesher.pixel_position(0.5, 0.5, 0.5,
        capture, 0, 4, 0.0)
    if center_front.distance_to(Vector3.ZERO) > 0.001:
        _fail("Front depth did not reconstruct model center " + str(center_front))
        return
    var center_side: Vector3 = Mesher.pixel_position(0.5, 0.5, 0.5,
        capture, 1, 4, 0.0)
    if center_side.distance_to(Vector3.ZERO) > 0.001:
        _fail("Side depth did not reconstruct model center " + str(center_side))
        return
    var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
    var depth := Image.create(32, 32, false, Image.FORMAT_RGBA8)
    img.fill(Color(0.8, 0.6, 0.6, 1))
    depth.fill(Color(0.5, 0.5, 0.5, 1))
    var reconstruction: Dictionary = Mesher.build_mesh(img, depth, capture, 0, 4, 0.0, 1)
    if reconstruction["mesh"] == null or int(reconstruction["triangles"]) < 100:
        _fail("Depth mesh not reconstructed")
        return
    var mesh: ArrayMesh = reconstruction["mesh"]
    var arrays: Array = mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var min_z := INF
    var max_z := -INF
    for p in vertices:
        min_z = minf(min_z, p.z)
        max_z = maxf(max_z, p.z)
    if absf(max_z - min_z) > 0.001:
        _fail("Constant-depth surface is not planar")
        return
    for y in range(32):
        for x in range(16, 32):
            img.set_pixel(x, y, Color(0, 0, 0, 0))
    reconstruction = Mesher.build_mesh(img, depth, capture, 0, 4, 0.0, 1)
    if int(reconstruction["triangles"]) >= 1000:
        _fail("Hidden alpha pixels were not culled")
        return
    var bad := Mesher.capture_from_manifest({"schema_version": 9})
    if not bad.is_empty():
        _fail("Unsupported manifest accepted")
        return
    print("LIE-03 MESHER PASS center_front=true center_side=true depth_mesh=true alpha_cull=true")
    quit(0)

func _fail(error: String) -> void:
    printerr("LIE-03 MESHER FAIL ", error)
    quit(1)
