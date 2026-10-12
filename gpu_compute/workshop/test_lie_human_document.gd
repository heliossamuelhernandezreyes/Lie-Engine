extends SceneTree
const Human=preload("res://workshop/lie_human_document.gd")
var checks: int=0
var failed: bool=false
func check(value: bool,message: String) -> void:
    checks+=1
    if not value: failed=true;push_error(message)
func _initialize() -> void:
    var doc:=Human.new();var original: Dictionary=doc.state.duplicate(true)
    check(doc.validate(original)=="","default human document")
    check(doc.dispatch({"op":"set_values","values":{"head_yaw":20,"sss":.5}})["ok"],"valid authoring")
    var revision: int=doc.revision;var good: Dictionary=doc.state.duplicate(true)
    for values in [{"head_yaw":26},{"sss":-1},{"distance":0},{"roughness":NAN},{"light_color":[1,2,1]},{"light_color":[1,1]},{"shadows":1},{"unknown":0},{"head_yaw":0,"jaw_drop":2}]:
        var result: Dictionary=doc.dispatch({"op":"set_values","values":values})
        check(not result["ok"] and doc.state==good and doc.revision==revision,"atomic invalid human edit")
    check(not doc.dispatch({"op":"set_values","expected_revision":0,"values":{"head_yaw":0}})["ok"],"stale agent revision")
    check(not doc.dispatch({"op":"set_time","value":INF})["ok"],"nonfinite time")
    check(doc.dispatch({"op":"undo"})["ok"] and doc.state==original,"undo human edit")
    check(doc.dispatch({"op":"redo"})["ok"] and doc.state==good,"redo human edit")
    check(doc.dispatch({"op":"save_document"})["ok"],"save human document")
    check(doc.dispatch({"op":"set_values","values":{"head_yaw":-10}})["ok"],"change human document")
    check(doc.dispatch({"op":"load_document"})["ok"] and doc.state==good,"reload saved authoring")
    check(doc.dispatch({"op":"set_playing","value":true})["ok"],"animation enabled")
    doc.dispatch({"op":"set_time","value":1})
    var evaluated: Dictionary=doc.evaluated()
    check(absf(float(evaluated["head_yaw"])-20)<.00001,"deterministic evaluated head animation")
    check(doc.state["head_yaw"]==20,"evaluation keeps authored controls")
    check(doc.dispatch({"op":"snapshot"})["snapshot"]["master"]=="lie-human-lee-perry-smith-v1","master identity")
    print("LIE20 HUMAN DOCUMENT ","FAIL" if failed else "PASS"," ",checks," checks");quit(1 if failed else 0)
