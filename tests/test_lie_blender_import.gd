extends SceneTree
## Requires generated 4-angle Blender surface fixture to exist in res://.
const SurfaceNode = preload("res://scripts/lie_surface_node.gd")

func _initialize() -> void:
    call_deferred("_check")

func _check() -> void:
    var camera := Camera3D.new()
    camera.name = "LieBlenderTestCamera"
    camera.current = true
    camera.position = Vector3(0, 2.0, 6)
    root.add_child(camera)
    camera.look_at(Vector3.ZERO, Vector3.UP)
    var node: Node3D = SurfaceNode.new()
    node.name = "LieBlenderAsset"
    node.asset_id = "demo_shard"
    node.azimuth_steps = 4
    node.elevation_degrees = PackedFloat32Array([-30.0, 0.0, 30.0])
    root.add_child(node)
    node.call("update_surface")
    var key: String = node.get("current_view_code")
    if key != "az_00_el_02" and key != "az_00_el_01":
        _fail("Unexpected front sample code " + key)
        return
    if not bool(node.get("using_captured_surface")):
        _fail("RGB/normal/depth Blender triplet did not load")
        return
    var entries: Dictionary = node.get("cache")
    var channels: Dictionary = entries[key]
    if not bool(channels["captured"]):
        _fail("Loaded placeholder instead of Blender")
        return
    camera.position = Vector3(6, 2.0, 0)
    camera.look_at(Vector3.ZERO, Vector3.UP)
    node.call("update_surface")
    if not bool(node.get("using_captured_surface")):
        _fail("No Blender capture at the side")
        return
    print("LIE-02 BLENDER IMPORT PASS front=%s side=%s" % [key, str(node.get("current_view_code"))])
    quit(0)

func _fail(msg: String) -> void:
    printerr("LIE-02 BLENDER IMPORT FAIL ", msg)
    quit(1)
