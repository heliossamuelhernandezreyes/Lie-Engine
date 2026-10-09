extends SceneTree
## Actual Godot viewport captures at two camera positions, without postprocessing.
## Visual evidence of view selection; not a quality or performance benchmark.
const SCENE = preload("res://scenes/lie_lab.tscn")

func _initialize() -> void:
    call_deferred("_capture")


func _capture() -> void:
    var world: Node3D = SCENE.instantiate()
    root.add_child(world)
    var camera: Camera3D = world.get_node("LieCamera") as Camera3D
    var visual: Node3D = world.get_node("LieNode_Demo") as Node3D
    world.set_process(false)
    if camera == null or visual == null:
        _fail("Missing camera or Lie node")
        return
    var keys: Array[String] = []
    var frame_hashes: Array[String] = []
    for shot in range(2):
        var angle: float = 0.0 if shot == 0 else PI / 2.0
        camera.global_position = Vector3(7.5 * sin(angle), 3.35, 7.5 * cos(angle))
        camera.look_at(Vector3(0, 1.4, 0), Vector3.UP)
        visual.call("_process", 0.0)
        keys.append(str(visual.get("current_view_code")))
        for _frame in range(6):
            await process_frame
        var image: Image = root.get_texture().get_image()
        if image == null or image.is_empty() or image.get_width() < 640:
            _fail("Captured framebuffer is missing or too small")
            return
        var filename: String = "user://lie-01-view-%d.png" % shot
        if image.save_png(filename) != OK:
            _fail("Could not save viewport PNG")
            return
        frame_hashes.append(FileAccess.get_sha256(filename))
    if keys[0] == keys[1] or frame_hashes[0] == frame_hashes[1]:
        _fail("Different camera positions did not change view codes and pixels")
        return
    print("LIE-01 CAPTURE PASS views=%s,%s hashes=%s,%s" %
        [keys[0], keys[1], frame_hashes[0], frame_hashes[1]])
    quit(0)


func _fail(reason: String) -> void:
    printerr("LIE-01 CAPTURE FAIL ", reason)
    quit(1)
