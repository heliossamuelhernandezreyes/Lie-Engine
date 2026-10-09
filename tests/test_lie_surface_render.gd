extends SceneTree
## Pixel evidence only; different screenshots are not a quality benchmark.
const Lab = preload("res://scenes/lie_surface_lab.tscn")

func _initialize() -> void:
    call_deferred("_capture")

func _capture() -> void:
    var lab: Node3D = Lab.instantiate()
    root.add_child(lab)
    var lie: Node3D = lab.get_node("LieSurfaceNode")
    lab.set_process(false)
    lie.set_process(false)
    var camera: Camera3D = lab.get_node("LieCamera")
    camera.position = Vector3(0, 3.1, 7.2)
    camera.look_at(Vector3(0, 1.4, 0), Vector3.UP)
    lie.call("update_surface")
    var views := []
    for warm in [true, false]:
        lab.call("set_warm_light", warm)
        for frame in range(8):
            await process_frame
        var image: Image = root.get_texture().get_image()
        if image.is_empty() or image.get_width() < 640:
            _fail("No real Godot framebuffer")
            return
        var filename: String = "res://lie-02-%s.png" % ("warm" if warm else "cool")
        if image.save_png(filename) != OK:
            _fail("Cannot save viewport capture")
            return
        views.append(FileAccess.get_sha256(filename))
    if views[0] == views[1]:
        _fail("Lighting change had no pixel effect")
        return
    print("LIE-02 LIGHT CAPTURE PASS identical_camera=true pixel_hashes_differ=true")
    quit(0)

func _fail(message: String) -> void:
    printerr("LIE-02 LIGHT CAPTURE FAIL ", message)
    quit(1)
