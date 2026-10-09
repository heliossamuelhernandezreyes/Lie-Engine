extends SceneTree
const Lab = preload("res://scenes/lie_surface_lab.tscn")

func _initialize() -> void:
    call_deferred("_check")

func _check() -> void:
    var lab: Node3D = Lab.instantiate()
    root.add_child(lab)
    var lie: Node3D = lab.get_node_or_null("LieSurfaceNode") as Node3D
    var body: Node = lab.get_node_or_null("InvisiblePhysicsProxy")
    var reference: MeshInstance3D = lab.get_node_or_null("Reference3D") as MeshInstance3D
    if lie == null or not body is StaticBody3D or reference == null:
        _fail("Missing 3D collision, surface node, or reference")
        return
    if reference.visible or lie.get_node_or_null("LieSurfaceVisual") == null:
        _fail("Reference mesh unexpectedly visible / visual node missing")
        return
    var shader_material: ShaderMaterial = lie.get("surface_material") as ShaderMaterial
    if shader_material == null or shader_material.shader == null:
        _fail("Missing dynamic relighting shader")
        return
    var cache: Dictionary = lie.get("cache")
    var code: String = lie.get("current_view_code")
    if code == "" or not cache.has(code):
        _fail("View code was not selected from camera")
        return
    var channels: Dictionary = cache[code]
    for channel in ["albedo", "normal", "depth"]:
        var tex: Texture2D = channels[channel]
        if tex == null or tex.get_width() <= 0:
            _fail("Missing real Texture2D for " + channel)
            return
    # CI may have generated real Blender captures, while a local checkout
    # may fall back to synthetic images. Both are explicit modes.
    if bool(lie.get("using_captured_surface")) != bool(channels["captured"]):
        _fail("Photographic versus synthetic source provenance is inconsistent")
        return
    lab.set_process(false)
    lie.set_process(false)
    lab.set_warm_light(false)
    var light0: Vector3 = shader_material.get_shader_parameter("light_rgb")
    lab.set_warm_light(true)
    var light1: Vector3 = shader_material.get_shader_parameter("light_rgb")
    if light0 == light1:
        _fail("Light source values do not alter shader")
        return
    print("LIE-02 SURFACE CONTRACT PASS channel_triplet=loaded reference=hidden light=mutable")
    quit(0)

func _fail(reason: String) -> void:
    printerr("LIE-02 SURFACE CONTRACT FAIL ", reason)
    quit(1)
