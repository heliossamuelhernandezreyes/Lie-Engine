extends SceneTree
const Lab = preload("res://scenes/lie_depth_lab.tscn")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var world: Node3D = Lab.instantiate()
    root.add_child(world)
    var red: Node3D = world.get_node_or_null("NearRedGroup") as Node3D
    var blue: Node3D = world.get_node_or_null("FarBlueGroup") as Node3D
    var camera: Camera3D = world.get_node_or_null("LieCamera") as Camera3D
    if red == null or blue == null or camera == null:
        _fail("Missing nodes or camera")
        return
    world.set_process(false)
    red.set_process(false)
    blue.set_process(false)
    red.set("azimuth_steps", 4)
    blue.set("azimuth_steps", 4)
    red.call("update_surface")
    blue.call("update_surface")
    for node in [red, blue]:
        if int(node.get("current_triangle_count")) <= 0:
            _fail("Depth geometry has no triangles")
            return
        var mesh_node: MeshInstance3D = node.get_node_or_null("DepthSurface") as MeshInstance3D
        if mesh_node == null or mesh_node.mesh == null or not mesh_node.visible:
            _fail("No active depth surface mesh")
            return
        if mesh_node.material_override == null or not mesh_node.material_override is ShaderMaterial:
            _fail("Depth shader missing from mesh")
            return
    for path in ["NearRedGroup_InvisibleCollider", "FarBlueGroup_InvisibleCollider"]:
        if not world.get_node(path) is StaticBody3D:
            _fail("Invisible physical collision missing")
            return
    print("LIE-03 SCENE PASS nodes=2 depth_meshes=2 colliders=2")
    quit(0)

func _fail(err: String) -> void:
    printerr("LIE-03 SCENE FAIL ", err)
    quit(1)
