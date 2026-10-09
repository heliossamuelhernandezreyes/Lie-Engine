extends SceneTree
const Scene = preload("res://scenes/lie_lab.tscn")

func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var world: Node3D = Scene.instantiate()
    root.add_child(world)
    var body: Node = world.get_node_or_null("InvisiblePhysicsProxy")
    var node: Node = world.get_node_or_null("LieNode_Demo")
    var camera: Node = world.get_node_or_null("Camera3D")
    if not body is StaticBody3D or node == null or not camera is Camera3D:
        _fail("Missing actual physical proxy, camera or Lie node")
        return
    var collider: Node = body.get_node_or_null("CollisionShape3D")
    var image: Node = node.get_node_or_null("Visual")
    if not collider is CollisionShape3D or not image is Sprite3D:
        _fail("No physical collider or Sprite3D")
        return
    var meshes: Array[MeshInstance3D] = []
    _collect_rendered_meshes(world, meshes)
    if not meshes.is_empty():
        _fail("Prototype contains a rendered conventional 3D mesh")
        return
    print("LIE-01 PROXY PASS physics=3D invisible mesh_count=0 visual=Sprite3D")
    quit(0)


func _collect_rendered_meshes(parent: Node, out: Array[MeshInstance3D]) -> void:
    if parent is MeshInstance3D and parent.visible:
        out.append(parent)
    for child in parent.get_children():
        _collect_rendered_meshes(child, out)


func _fail(why: String) -> void:
    printerr("LIE-01 PROXY FAIL: ", why)
    quit(1)
