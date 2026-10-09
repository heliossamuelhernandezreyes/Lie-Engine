extends SceneTree
const NodeScript = preload("res://scripts/lie_depth_node.gd")
const Rect = preload("res://scripts/lie_occluder_rect.gd")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var world := Node3D.new()
    root.add_child(world)
    var camera := Camera3D.new()
    camera.name = "LieCamera"
    camera.current = true
    camera.position = Vector3(0, 0, 5)
    world.add_child(camera)
    camera.look_at(Vector3.ZERO, Vector3.UP)
    var wall: Node3D = Rect.new()
    wall.name = "OpaqueRect"
    wall.position = Vector3(0, 0, 2)
    wall.set("half_extent", Vector2(4, 4))
    world.add_child(wall)
    var node: Node3D = NodeScript.new()
    node.name = "BehindRect"
    node.set("azimuth_steps", 4)
    node.set("elevation_degrees", PackedFloat32Array([-30, 0, 30]))
    world.add_child(node)
    node.set_process(false)
    node.call("update_surface")
    if str(node.get("visibility_reason")) != "occluded":
        _fail("Opaque wall failed to hide entire node")
        return
    if int(node.get("geometry_builds")) != 0 or not node.get("cache").is_empty():
        _fail("Occluded node loaded data or built geometry BEFORE visibility")
        return

    wall.position.x = 10
    node.call("update_surface")
    if str(node.get("visibility_reason")) != "" or int(node.get("geometry_builds")) < 1:
        _fail("Moving wall away did not restore the surface")
        return
    var built: int = int(node.get("geometry_builds"))
    node.position = Vector3(100, 0, 0)
    node.call("update_surface")
    if str(node.get("visibility_reason")) != "frustum" or int(node.get("geometry_builds")) != built:
        _fail("Offscreen group was still reconstructed")
        return

    node.position = Vector3.ZERO
    wall.position.x = 0
    wall.set("half_extent", Vector2(0.35, 0.35))
    node.call("update_surface")
    if str(node.get("visibility_reason")) != "":
        _fail("Partial occlusion MUST NOT discard node")
        return
    if int(node.get("skipped_for_visibility")) < 2:
        _fail("Expected two distinct visibility rejections")
        return
    print("LIE-04 CULL PIPELINE PASS hidden_builds=0 frustum=no-build partial_visible=true")
    quit(0)

func _fail(message: String) -> void:
    printerr("LIE-04 CULL PIPELINE FAIL ", message)
    quit(1)
