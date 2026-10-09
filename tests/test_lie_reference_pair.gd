extends SceneTree
## Same-camera evidence: photographed Lie surface vs imported source GLB.
## No quality ranking, geometry match, or performance assertion.
const Lab = preload("res://scenes/lie_surface_lab.tscn")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var src_path := "res://assets/captures/demo_shard/source.glb"
    var src_scene: PackedScene = load(src_path) as PackedScene
    if src_scene == null:
        _fail("The original GLB fixture is not imported into Godot")
        return
    var world: Node3D = Lab.instantiate()
    root.add_child(world)
    world.set_process(false)
    var node: Node3D = world.get_node("LieSurfaceNode")
    node.set_process(false)
    node.set("asset_id", "demo_shard")
    node.set("azimuth_steps", 4)
    node.set("elevation_degrees", PackedFloat32Array([-30.0, 0.0, 30.0]))
    node.position = Vector3(0, 0.5, 0)
    node.set("current_view_code", "")
    var camera: Camera3D = world.get_node("LieCamera")
    camera.position = Vector3(0, 1.1, 7.2)
    camera.look_at(Vector3(0, 0.5, 0), Vector3.UP)
    node.call("update_surface")
    if not bool(node.get("using_captured_surface")):
        _fail("Lie capture not from the same real fixture")
        return
    for child in world.get_children():
        if child is CanvasLayer:
            child.visible = false
    var reference: Node3D = src_scene.instantiate() as Node3D
    reference.name = "NativeGodotGLB"
    world.add_child(reference)
    reference.visible = false
    var key: String = str(node.get("current_view_code"))
    var basis: Transform3D = camera.global_transform
    var outputs: Array[String] = []
    for lie_view in [true, false]:
        node.visible = lie_view
        reference.visible = not lie_view
        for i in range(8):
            await process_frame
        if camera.global_transform != basis or key != str(node.get("current_view_code")):
            _fail("Matched camera moved between images")
            return
        var image: Image = root.get_texture().get_image()
        if image.is_empty() or image.get_width() < 640:
            _fail("Invalid viewport capture")
            return
        var name: String = "res://lie-02-%s.png" % ("lie-surface" if lie_view else "reference-3d")
        if image.save_png(name) != OK:
            _fail("Failed to export native image")
            return
        outputs.append(FileAccess.get_sha256(name))
    if outputs[0] == outputs[1]:
        _fail("Lie and real 3D were not visually distinct")
        return
    print("LIE-02 3D REFERENCE PAIR PASS camera=matched source=identical capture=real asset")
    quit(0)

func _fail(message: String) -> void:
    printerr("LIE-02 REFERENCE PAIR FAIL ", message)
    quit(1)
