extends SceneTree
const Rig=preload("res://lie26_rig.gd")
var checks: int=0
var failed: bool=false
func check(ok: bool,message: String) -> void:
    checks+=1
    if not ok:failed=true;push_error(message)

func _initialize() -> void:
    var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/lie26-rig.json"))
    var bones: Array=fixture["bones"]
    for case in fixture["cases"]:
        var result: Dictionary=Rig.evaluate(bones,case["pose"])
        for i in range(15):
            check(result["origins"][i].distance_to(Rig.vector(case["origins"][i]))<.000003,"Independent source-axis FK "+str(case["name"]))
            var q: Quaternion=result["rotations"][i]
            check(absf(q.dot(Quaternion(case["rotations"][i][0],case["rotations"][i][1],case["rotations"][i][2],case["rotations"][i][3])))>.999999,"Independent joint rotation")
    check(not Rig.validate_pose({"right_elbow":141}),"Elbow limit")
    check(not Rig.validate_pose({"right_elbow":NAN}),"Nonfinite pose")
    check(not Rig.validate_pose({"right_elbow":true}),"Boolean pose")
    check(not Rig.validate_targets({"right_hand":{"position":[0,0,0],"pole":[0,1,0],"extra":1}}),"Unknown IK field")
    for key in Rig.CHAINS:
        var side: float=-1 if key.begins_with("right") else 1
        var target: Array=[side*.25,1.2,.36] if key.ends_with("hand") else [side*.075,.09,.20]
        var result: Dictionary=Rig.evaluate(bones,{}, {key:{"position":target,"pole":[side*.35,.6,1.0]}})
        check(result["ik"][key]["residual_m"]<.00002,"Reachable IK "+key)
        var far: Dictionary=Rig.evaluate(bones,{}, {key:{"position":[side*3,3,3],"pole":[side*.35,.6,1.0]}})
        check(far["ik"][key]["clamped"] and far["ik"][key]["hinge_deg"]<=140 and far["ik"][key]["residual_m"]>1,"Unreachable goal clamps "+key)
    for i in range(17):
        var walk: Dictionary=Rig.walk(i/16.0);var result: Dictionary=Rig.evaluate(bones,walk["pose"],walk["targets"])
        for side in ["right","left"]:
            check(result["ik"][side+"_foot"]["residual_m"]<.00003,"Procedural foot IK")
            check(result["origins"][11 if side=="right" else 14].y>=.0679,"Feet do not sink below target floor")
        var packet: PackedByteArray=Rig.packet(result)
        check(packet.size()==480,"Bone packet bytes")
    print("LIE26 RIG ","FAIL" if failed else "PASS"," ",checks," checks");quit(1 if failed else 0)
