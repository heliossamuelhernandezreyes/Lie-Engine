extends SceneTree
const Assembly=preload("res://lie_robot_assembly.gd")
const Rig=preload("res://lie26_rig.gd")
const Lab=preload("res://lie_robot_lab.gd")
var checks: int=0
var failed: bool=false
func expect(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;push_error("ROBOT RIG: "+label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://captures/robot_modular/catalog.json"));var lab:=Lab.new();var initial: Dictionary=lab.state.duplicate(true)
    expect(Rig.validate_pose(initial["pose"]),"Default pose respects semantic rig")
    expect(not Rig.validate_pose({"right_elbow":200}),"Unsafe joint range rejected")
    var max_length_error: float=0;var max_ik_error: float=0
    for mode in ["manual","walk","reach"]:
        for time in [0.0,.25,.5,.75]:
            var state: Dictionary=initial.duplicate(true);state["mode"]=mode;state["time"]=time
            var model: Dictionary=Assembly.build(catalog,state);var rig: Dictionary=model["rig"]
            expect(model["parts"].size()<=128,"Assembly instance budget")
            for pair in [[3,4],[4,5],[6,7],[7,8],[9,10],[10,11],[12,13],[13,14]]:
                var a: int=pair[0];var b: int=pair[1];var length: float=Rig.vector(catalog["rig"][a]["pivot"]).distance_to(Rig.vector(catalog["rig"][b]["pivot"]))
                expect(absf(rig["origins"][a].distance_to(rig["origins"][b])-length)<.00001,"Rigid bone lengths preserved")
            for report in rig["ik"].values():max_ik_error=maxf(max_ik_error,report["residual_m"]);expect(report["residual_m"]<.003,"Foot target reached")
            var packet: PackedFloat32Array=model["curves"]
            for curve in range(model["paths"].size()):
                var path: Dictionary=model["paths"][curve];var a: Vector3=Assembly.cable_position(Vector3(0,-.25,0),packet,curve);var b: Vector3=Assembly.cable_position(Vector3(0,.25,0),packet,curve)
                expect(a.distance_to(Rig.vector(path["endpoints"][0]))<.00001 and b.distance_to(Rig.vector(path["endpoints"][1]))<.00001,"Cable anchor continuity")
                var length: float=0;var previous: Vector3=a
                for i in range(1,129):
                    var p: Vector3=Assembly.cable_position(Vector3(0,-.25+.5*float(i)/128,0),packet,curve);length+=p.distance_to(previous);previous=p
                var error: float=absf(length-path["requested_length"]);max_length_error=maxf(max_length_error,error)
                expect(error<.003 and not path["clamped"],"Cable conserves calibrated rest length")
                for i in range(16):
                    var offset: int=(curve*16+i)*12;var n:=Vector3(packet[offset+4],packet[offset+5],packet[offset+6]);var t:=Vector3(packet[offset+8],packet[offset+9],packet[offset+10])
                    expect(absf(n.length()-1)<.00001 and absf(n.dot(t))<.00001,"Orthonormal transported cable frame")
                    var y: float=-.25+.5*float(i)/15;var p: Vector3=Assembly.cable_position(Vector3(.009,y,0),packet,curve);var c: Vector3=Assembly.cable_position(Vector3(0,y,0),packet,curve)
                    expect(absf(p.distance_to(c)-.009)<.00001,"Cable radius preserved")
                    expect(absf(Assembly.cable_jacobian(Vector3(.009,y,0),packet,curve).determinant())>.05,"Cable deformation remains invertible")
    var report: Dictionary={"checks":checks,"failed":failed,"max_cable_length_error_m":max_length_error,"max_ik_error_m":max_ik_error}
    var file:=FileAccess.open("res://robot-rig-verification.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close();print("ROBOT RIG ",JSON.stringify(report));lab.free();quit(1 if failed else 0)
