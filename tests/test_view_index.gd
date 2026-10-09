extends SceneTree
const ViewIndex = preload("res://scripts/lie_view_index.gd")
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")


func _check(actual: String, expected: String, label: String) -> void:
    if actual != expected:
        failures.append("%s expected %s got %s" % [label, expected, actual])


func _run() -> void:
    var el := PackedFloat32Array([-30.0, 0.0, 30.0])
    var origin := Transform3D.IDENTITY
    _check(ViewIndex.select_view(Vector3(0, 0, 8), origin, 16, el)["code"],
        "az_00_el_01", "front")
    _check(ViewIndex.select_view(Vector3(8, 0, 0), origin, 16, el)["code"],
        "az_04_el_01", "right")
    _check(ViewIndex.select_view(Vector3(0, 0, -8), origin, 16, el)["code"],
        "az_08_el_01", "back")
    _check(ViewIndex.select_view(Vector3(-8, 0, 0), origin, 16, el)["code"],
        "az_12_el_01", "left")
    _check(ViewIndex.select_view(Vector3(0, 8, 8), origin, 16, el)["code"],
        "az_00_el_02", "high")
    _check(ViewIndex.select_view(Vector3(0, -8, 8), origin, 16, el)["code"],
        "az_00_el_00", "low")

    var moved := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(25, 0, -7))
    _check(ViewIndex.select_view(Vector3(33, 0, -7), moved, 16, el)["code"],
        "az_00_el_01", "local rotation and translation")

    for i in range(16):
        var d: Vector3 = ViewIndex.direction_for_view(i, 16, 0.0)
        var code: String = ViewIndex.select_view(d * 10.0, origin, 16, el)["code"]
        _check(code, "az_%02d_el_01" % i, "roundtrip %d" % i)

    if failures.is_empty():
        print("LIE-01 ANGULAR INDEX PASS 23 assertions")
        quit(0)
    else:
        for error in failures:
            printerr("FAIL: ", error)
        quit(1)
