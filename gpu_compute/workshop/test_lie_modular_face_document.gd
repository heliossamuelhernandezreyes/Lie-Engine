extends SceneTree
const Doc=preload("res://workshop/lie_modular_face_document.gd")
var checks: int=0
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:push_error(label);quit(1)
func _initialize() -> void:
    var doc:=Doc.new();var original: Dictionary=doc.snapshot()
    for value in [-1,4,.5,"short",null]:
        check(not doc.dispatch({"op":"set_values","values":{"nose_index":value,"head_yaw":20}})["ok"],"Invalid selection rejected")
        check(doc.snapshot()==original,"Invalid selection is atomic")
    check(doc.dispatch({"op":"set_values","values":{"nose_index":3}})["ok"],"Select compatible asset")
    check(doc.dispatch({"op":"undo"})["ok"] and doc.state["nose_index"]==1,"Undo module")
    check(doc.dispatch({"op":"redo"})["ok"] and doc.state["nose_index"]==3,"Redo module")
    check(doc.dispatch({"op":"save_document"})["ok"],"Save module document")
    doc.dispatch({"op":"set_values","values":{"nose_index":0}})
    check(doc.dispatch({"op":"load_document"})["ok"] and doc.state["nose_index"]==3,"Restore module document")
    for seed_value in [0,1,17,99,2147483647]:
        var a:=Doc.new();var b:=Doc.new()
        check(a.dispatch({"op":"randomize","seed":seed_value})["ok"],"Seeded construction")
        b.dispatch({"op":"randomize","seed":seed_value})
        check(a.state==b.state and a.state["nose_index"] in [1.,2.,3.],"Repeatable compatible construction")
    original=doc.snapshot()
    for seed_value in [-1,.5,"seed",2147483648]:
        check(not doc.dispatch({"op":"randomize","seed":seed_value})["ok"] and doc.snapshot()==original,"Invalid seed is atomic")
    check(not doc.dispatch({"op":"randomize","seed":17,"expected_revision":-1})["ok"] and doc.snapshot()==original,"Randomization respects revision")
    check(doc.snapshot()["master"]=="lie-modular-face24","Separate identity from earlier face")
    print("LIE24 DOCUMENT PASS ",checks," checks");quit(0)
