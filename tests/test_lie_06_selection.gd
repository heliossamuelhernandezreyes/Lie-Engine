extends SceneTree
const Selector = preload("res://scripts/lie_06_view_selector.gd")
func _initialize() -> void:
    call_deferred("_check")
func _check() -> void:
    var el := PackedFloat32Array([-30.0,0.0,30.0])
    var target: Vector3 = Vector3(1,0,1).normalized()*6.0
    var selected: Array[Dictionary] = Selector.choose(target,Transform3D.IDENTITY,4,el,4)
    if selected.size()!=4:
        _fail("Expected four nearby directions")
        return
    var sum := 0.0
    var codes := []
    for view in selected:
        sum += float(view["weight"])
        codes.append(view["code"])
    if absf(sum-1.0)>0.0001:
        _fail("Angular weights do not normalize")
        return
    if not ("az_00_el_01" in codes and "az_01_el_01" in codes):
        _fail("Both 45-degree adjacent angular captures required")
        return
    var wrap: Array[Dictionary] = Selector.choose(Vector3(-0.01,0,1),
        Transform3D.IDENTITY,16,PackedFloat32Array([0]),4)
    if wrap.size()!=4 or wrap[0]["code"]!="az_00_el_00" or wrap[1]["code"]!="az_15_el_00":
        _fail("360-degree seam incorrect")
        return
    print("LIE-06 VIEW SELECTOR PASS nearest_four=true normalized=true wrap=true")
    quit(0)
func _fail(message: String) -> void:
    printerr("LIE-06 VIEW SELECTOR FAIL ",message)
    quit(1)
