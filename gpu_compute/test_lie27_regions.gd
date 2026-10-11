extends SceneTree
const Rig=preload("res://lie27_rig.gd")
const Old=preload("res://lie26_rig.gd")
var checks: int=0
var failed: bool=false
func check(ok: bool,message: String) -> void:
    checks+=1
    if not ok:failed=true;push_error(message)
func _initialize() -> void:
    var old: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/lie26-rig.json"))
    # Legacy body pivots are unchanged by adding controls for the fingers.
    for case in old["cases"]:
        var result: Dictionary=Rig.evaluate(old["bones"],case["pose"])
        for i in range(15):check(result["origins"][i].distance_to(Old.vector(case["origins"][i]))<.000003,"Legacy body FK")
    check(Rig.validate_pose({"right_index":90,"left_thumb":30}),"Finger controls accepted")
    check(not Rig.validate_pose({"right_index":91}),"Finger range rejected")
    check(not Rig.validate_pose({"left_little":NAN}),"Nonfinite finger rejected")
    var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/lie27-rig.json"))
    for case in fixture["cases"]:
        var result: Dictionary=Rig.evaluate(fixture["bones"],case["pose"])
        for i in range(45):
            check(result["origins"][i].distance_to(Rig.vector(case["origins"][i]))<.000003,"Independent finger/body origins")
            var expected:=Quaternion(case["rotations"][i][0],case["rotations"][i][1],case["rotations"][i][2],case["rotations"][i][3])
            check(absf(result["rotations"][i].dot(expected))>.999999,"Independent finger/body rotations")
    print("LIE27 REGIONS ","FAIL" if failed else "PASS"," ",checks," checks");quit(1 if failed else 0)
