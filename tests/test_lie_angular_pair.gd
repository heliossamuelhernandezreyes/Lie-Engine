extends SceneTree
const Pair = preload("res://scripts/lie_angular_pair.gd")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var el := PackedFloat32Array([-30.0, 0.0, 30.0])
    var origin := Transform3D.IDENTITY
    var first: Dictionary = Pair.choose(Vector3(0, 0, 10), origin, 4, el)
    if first["first_code"] != "az_00_el_01" or float(first["weight"]) > 0.0001:
        _fail("Cardinal frame should be unmixed")
        return
    var between: Dictionary = Pair.choose(Vector3(10, 0, 10), origin, 4, el)
    if between["first_code"] != "az_00_el_01" or between["next_code"] != "az_01_el_01" or absf(float(between["weight"]) - 0.5) > 0.0001:
        _fail("Angular midpoint should blend 50/50")
        return
    var wrap: Dictionary = Pair.choose(Vector3(-1.0, 0, 10), origin, 4, el)
    if wrap["first_code"] != "az_03_el_01" or wrap["next_code"] != "az_00_el_01":
        _fail("Azimuth seam must wrap")
        return
    var left: Dictionary = Pair.choose(Vector3(9.999, 0, 0.01), origin, 4, el)
    var right: Dictionary = Pair.choose(Vector3(9.999, 0, -0.01), origin, 4, el)
    if left["next_code"] != right["first_code"] or not (
            float(left["weight"]) > 0.99 and float(right["weight"]) < 0.01):
        _fail("Selection discontinuity around sector boundary")
        return
    print("LIE-04 ANGULAR PAIR PASS midpoint=0.5 wrap=true sector_continuity=true")
    quit(0)

func _fail(message: String) -> void:
    printerr("LIE-04 ANGULAR PAIR FAIL ", message)
    quit(1)
