extends SceneTree
## Tests TWO actual depth-reconstructed meshes with complementary Bayer coverage.
## Shader material tints intentionally differ so mixed views are measurable.
const LieNode = preload("res://scripts/lie_depth_node.gd")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var world := Node3D.new()
    root.add_child(world)
    var camera := Camera3D.new()
    camera.name = "AngularCamera"
    camera.current = true
    camera.fov = 50
    world.add_child(camera)

    var node: Node3D = LieNode.new()
    node.name = "LieDepthAsset"
    node.set("azimuth_steps", 4)
    node.set("elevation_degrees", PackedFloat32Array([-30, 0, 30]))
    node.set("reconstruction_stride", 1)
    world.add_child(node)
    node.set_process(false)
    var m0: ShaderMaterial = node.get("material") as ShaderMaterial
    var m1: ShaderMaterial = node.get("secondary_material") as ShaderMaterial
    m0.set_shader_parameter("node_tint", Vector3(2.2, 0.0, 0.0))
    m1.set_shader_parameter("node_tint", Vector3(0.0, 0.0, 3.3))
    for mat in [m0, m1]:
        mat.set_shader_parameter("ambient_level", 1.0)
        mat.set_shader_parameter("light_intensity", 0.0)

    var counters := []
    for az_degrees in [0.0, 45.0, 90.0]:
        var angle: float = deg_to_rad(az_degrees)
        camera.position = Vector3(6.0 * sin(angle), 0, 6.0 * cos(angle))
        camera.look_at(Vector3.ZERO, Vector3.UP)
        node.call("update_surface")
        if not bool(node.get("using_captured_surface")):
            _fail("The CI test requires real imported Blender depth textures")
            return
        for _frame in range(12):
            await process_frame
        var image: Image = root.get_texture().get_image()
        if image.is_empty():
            _fail("Godot gave an empty viewport")
            return
        var red_pixels := 0
        var blue_pixels := 0
        var cx: int = image.get_width() / 2
        var cy: int = image.get_height() / 2
        for y in range(cy - 80, cy + 80):
            for x in range(cx - 80, cx + 80):
                var pixel := image.get_pixel(x, y)
                if pixel.r > 0.14 and pixel.r > pixel.b * 1.8:
                    red_pixels += 1
                if pixel.b > 0.14 and pixel.b > pixel.r * 1.8:
                    blue_pixels += 1
        var filename: String = "res://lie-04-angle-%d.png" % int(az_degrees)
        if image.save_png(filename) != OK:
            _fail("Could not save the native frame")
            return
        counters.append([red_pixels, blue_pixels])
    # At 45 degrees, both passes must be visible. At the sector ends the
    # secondary pass must be inactive, and primaries remain visible.
    if counters[0][0] < 40 or counters[0][1] > 10:
        _fail("Cardinal 0 degree frame should use only the primary view: " + str(counters))
        return
    if counters[1][0] < 30 or counters[1][1] < 30:
        _fail("Midpoint did not contain BOTH reconstructed views: " + str(counters))
        return
    if counters[2][0] < 40 or counters[2][1] > 10:
        _fail("Cardinal 90 degree frame should use only primary view: " + str(counters))
        return
    print("LIE-04 ANGULAR GPU PASS 0=first 45=both 90=next counts=" + str(counters))
    quit(0)

func _fail(message: String) -> void:
    printerr("LIE-04 ANGULAR GPU FAIL ", message)
    quit(1)
