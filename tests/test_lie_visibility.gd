extends SceneTree
const Visibility = preload("res://scripts/lie_visibility.gd")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var camera := Camera3D.new()
    camera.name = "VisibilityCamera"
    camera.current = true
    camera.fov = 65.0
    camera.position = Vector3(0, 0, 5)
    root.add_child(camera)
    camera.look_at(Vector3.ZERO)
    if not Visibility.in_frustum(camera, Vector3.ZERO, 0.5):
        _fail("Sphere in center incorrectly culled")
        return
    if Visibility.in_frustum(camera, Vector3(100, 0, 0), 0.5):
        _fail("Object far outside view not culled")
        return
    if Visibility.in_frustum(camera, Vector3(0, 0, 100), 0.5):
        _fail("Object behind camera not culled")
        return
    if not Visibility.in_frustum(camera, Vector3(0, 0, 4.98), 0.5):
        _fail("Intersecting near plane incorrectly culled")
        return

    var wall := Transform3D.IDENTITY
    wall.origin = Vector3(0, 0, 2.0)
    var big := Vector2(3.0, 3.0)
    if not Visibility.covered_by_rectangle(camera.position, Vector3.ZERO,
            0.65, wall, big):
        _fail("Complete rectangular occlusion not recognized")
        return
    if Visibility.covered_by_rectangle(camera.position, Vector3(5.0, 0, 0),
            0.65, wall, big):
        _fail("Partially uncovered object MUST remain visible")
        return
    if Visibility.covered_by_rectangle(camera.position, Vector3(0, 0, 2),
            0.65, wall, big):
        _fail("Object intersecting wall cannot be culled")
        return
    if Visibility.covered_by_rectangle(camera.position, Vector3(0, 0, 3.7),
            0.65, wall, big):
        _fail("Object on camera side cannot be culled")
        return
    if Visibility.covered_by_rectangle(camera.position, Vector3.ZERO,
            0.65, wall, Vector2(0.15, 0.15)):
        _fail("Small wall cannot fully cover cube")
        return
    print("LIE-04 VISIBILITY PASS nearplane=conservative frustum=true rectangular_occlusion=conservative")
    quit(0)

func _fail(message: String) -> void:
    printerr("LIE-04 VISIBILITY FAIL ", message)
    quit(1)
