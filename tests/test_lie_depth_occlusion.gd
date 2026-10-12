extends SceneTree
## LIE-03 acceptance: two independently positioned depth reconstructions
## write to the SAME GPU depth buffer. Camera reversal must reverse foreground.
## Uses actual Blender triplets from CI; this is not synthetic color-only testing.
const LAB = preload("res://scenes/lie_depth_lab.tscn")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var world: Node3D = LAB.instantiate()
    root.add_child(world)
    world.set_process(false)
    var red: Node3D = world.get_node("NearRedGroup")
    var blue: Node3D = world.get_node("FarBlueGroup")
    var camera: Camera3D = world.get_node("LieCamera")
    for node in [red, blue]:
        node.set_process(false)
        node.set("azimuth_steps", 4)
        node.set("elevation_degrees", PackedFloat32Array([-30.0, 0.0, 30.0]))
        node.set("current_view_code", "")
        node.get("cache").clear()
        node.get("_cache_fifo").clear()
    var redmat: ShaderMaterial = red.get("material") as ShaderMaterial
    var bluemat: ShaderMaterial = blue.get("material") as ShaderMaterial
    redmat.set_shader_parameter("node_tint", Vector3(4, 0, 0))
    bluemat.set_shader_parameter("node_tint", Vector3(0, 0, 5))
    redmat.set_shader_parameter("ambient_level", 1.0)
    bluemat.set_shader_parameter("ambient_level", 1.0)
    redmat.set_shader_parameter("light_intensity", 0.0)
    bluemat.set_shader_parameter("light_intensity", 0.0)
    for child in world.get_children():
        if child is CanvasLayer:
            child.visible = false

    var result := []
    for front in [true, false]:
        camera.position = Vector3(0, 1.4, 8.5) if front else Vector3(0, 1.4, -8.5)
        camera.look_at(Vector3(0, 1.4, -0.45), Vector3.UP)
        red.call("update_surface")
        blue.call("update_surface")
        for node in [red, blue]:
            if not bool(node.get("using_captured_surface")):
                _fail("Real Blender channels missing, synthetic fallback used")
                return
            if int(node.get("current_triangle_count")) <= 0:
                _fail("Rendered group has zero reconstructed triangles")
                return
        for _frame in range(10):
            await process_frame
        var image: Image = root.get_texture().get_image()
        if image == null or image.is_empty():
            _fail("No Godot framebuffer")
            return
        var name := "res://lie-03-%s.png" % ("front-red" if front else "back-blue")
        if image.save_png(name) != OK:
            _fail("Could not save occlusion comparison")
            return
        # Sample 21x21 center; require foreground tint, not merely different hashes.
        var reds := 0
        var blues := 0
        for py in range(image.get_height() / 2 - 10, image.get_height() / 2 + 11):
            for px in range(image.get_width() / 2 - 10, image.get_width() / 2 + 11):
                var pixel: Color = image.get_pixel(px, py)
                if pixel.r > pixel.b * 1.7 and pixel.r > 0.08:
                    reds += 1
                elif pixel.b > pixel.r * 1.7 and pixel.b > 0.08:
                    blues += 1
        result.append({"red": reds, "blue": blues})
    if int(result[0]["red"]) < 80 or int(result[0]["red"]) < int(result[0]["blue"]) * 3:
        _fail("Front Z occlusion not red-dominant: " + str(result))
        return
    if int(result[1]["blue"]) < 80 or int(result[1]["blue"]) < int(result[1]["red"]) * 3:
        _fail("Reverse-camera Z occlusion not blue-dominant: " + str(result))
        return
    print("LIE-03 OCCLUSION PASS camera_front=red camera_back=blue samples=" + str(result))
    quit(0)

func _fail(reason: String) -> void:
    printerr("LIE-03 OCCLUSION FAIL ", reason)
    quit(1)
