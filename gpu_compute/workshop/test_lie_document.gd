extends SceneTree
const Doc=preload("res://workshop/lie_document.gd")
const Collision=preload("res://workshop/lie_collision.gd")
var checks: int=0
var failed: bool=false
func expect(value: bool,message: String) -> void:
    checks+=1
    if not value: failed=true; push_error("LIE18 DOCUMENT FAIL: "+message)
func equivalent(a: Variant,b: Variant) -> bool:
    if Doc.numeric(a) and Doc.numeric(b): return absf(float(a)-float(b))<1e-12
    if a is Array and b is Array:
        if a.size()!=b.size(): return false
        for i in range(a.size()):
            if not equivalent(a[i],b[i]): return false
        return true
    if a is Dictionary and b is Dictionary:
        if a.size()!=b.size(): return false
        for key in a:
            if not b.has(key) or not equivalent(a[key],b[key]): return false
        return true
    return a==b
func _initialize() -> void:
    var doc:=Doc.new()
    expect(Doc.validate(doc.state)=="","Default document")
    var initial: Dictionary=doc.snapshot()
    var rejected: Dictionary=doc.dispatch({"op":"batch","commands":[{"op":"add_piece","id":"new_part"},{"op":"update_piece","id":"head","values":{"parent":"eye_l"}}]})
    expect(not rejected["ok"] and rejected["error"]=="cycle","Cycle in atomic batch")
    expect(doc.snapshot()==initial,"Rejected batch does not partially modify scene")
    expect(not doc.dispatch({"op":"set_playing","value":true,"expected_revision":99})["ok"],"Revision conflict")
    expect(not doc.dispatch({"op":"update_piece","id":"torso","values":{"scale":[0,1,1]}})["ok"],"Singular scale")
    expect(not doc.dispatch({"op":"update_piece","id":"torso","values":{"position":[NAN,1,1]}})["ok"],"NaN transform")
    expect(not doc.dispatch({"op":"set_track","id":"head","keys":[[1,0],[.5,20]]})["ok"],"Unordered track")
    expect(not doc.dispatch({"op":"set_track","id":"head","keys":[[-.5,0]]})["ok"],"Negative key time")
    expect(not doc.dispatch({"op":"set_light","index":0,"values":{"radius":0}})["ok"],"Invalid radius")
    expect(not doc.dispatch({"op":"set_settings","values":{"rain_count":25}})["ok"],"Optical budget")
    expect(not doc.dispatch({"op":"eval","code":"arbitrary"})["ok"],"No arbitrary code execution")
    expect(not doc.dispatch({"op":"update_piece","id":"head","values":{"slot":29}})["ok"],"Stable slots cannot be edited")
    expect(doc.dispatch({"op":"duplicate_piece","id":"copy_head","source":"head","values":{"position":[.8,1,0]}})["ok"],"Duplicate")
    var copy: Dictionary=doc.state["pieces"][Doc.index_of(doc.state,"copy_head")]
    expect(copy["slot"]==15 and copy["master"]=="box","Duplicate reuses master, chooses new slot")
    expect(doc.dispatch({"op":"undo"})["ok"] and doc.state==initial["document"],"Undo restores entire transaction")
    expect(doc.dispatch({"op":"redo"})["ok"] and Doc.index_of(doc.state,"copy_head")>=0,"Redo")
    expect(doc.dispatch({"op":"remove_piece","id":"head"})["ok"] and Doc.index_of(doc.state,"eye_l")==-1,"Removal includes descendants and tracks")
    expect(doc.dispatch({"op":"undo"})["ok"],"Undo deletion")
    var scaled: Dictionary=doc.state.duplicate(true)
    scaled["tracks"]={}
    scaled["pieces"][0]["scale"]=[4,4,4]
    var e: Dictionary=Doc.evaluate(doc.state,0)
    var es: Dictionary=Doc.evaluate(scaled,0)
    expect((e["joints"]["head"] as Transform3D).is_equal_approx(es["joints"]["head"]),"Parent shape scale does not deform child joint")
    expect((Doc.evaluate(doc.state,.5)["joints"]["arm_l"] as Transform3D).is_equal_approx(Doc.evaluate(doc.state,2.5)["joints"]["arm_l"]),"Absolute-time looping independent of FPS")
    expect(absf(Doc.track_angle([[0,0],[1,40]],.5,0)-20)<.000001,"Interpolated key")
    var cycle_clear: bool=true
    var example: Dictionary=Doc.default_state()
    for frame in range(120):
        if not Collision.diagnostics(example,Doc.evaluate(example,float(frame)/60)).is_empty(): cycle_clear=false
    expect(cycle_clear,"Default animation has no nonconnected OBB or floor penetration across its cycle")
    var unit:=Transform3D.IDENTITY
    expect(Collision.overlap(unit,Transform3D(Basis(Vector3.UP,.6),Vector3(.4,0,0))),"Rotated OBB overlap")
    expect(not Collision.overlap(unit,Transform3D(Basis.IDENTITY,Vector3(1,0,0))),"Touching OBB is allowed")
    expect(not Collision.overlap(unit,Transform3D(Basis(Vector3.UP,.6),Vector3(3,0,0))),"Separated OBB")
    expect(Collision.segment_hit(Vector3(0,2,0),Vector3(0,-2,0),unit),"Fast drop segment does not tunnel")
    expect(not Collision.segment_hit(Vector3(2,2,0),Vector3(2,-2,0),unit),"Missed drop segment")
    var duration: float=sqrt(2*3.85/9.81)
    expect(absf(Collision.rain_position(0,duration*.5).y-(2.8-3.85*.25))<.00001,"Ballistic fall")
    expect(Collision.rain_position(0,0).is_equal_approx(Collision.rain_position(0,duration)),"Deterministic droplet cycle")
    var saved: Dictionary=doc.state.duplicate(true)
    expect(doc.save_document("user://workshop/acceptance.lie.json")["ok"],"Atomic save")
    doc.dispatch({"op":"set_settings","values":{"fluid":"water"}})
    var loaded: Dictionary=doc.load_document("user://workshop/acceptance.lie.json")
    expect(loaded["ok"] and equivalent(doc.state,saved),"Save/load round trip")
    expect(not doc.save_document("user://workshop/../../unsafe.lie.json")["ok"],"Save confined to document directory")
    expect(doc.dispatch({"op":"set_camera","values":{"yaw_deg":60}})["ok"],"Agent controls camera")
    expect(doc.dispatch({"op":"set_material","name":"steel","values":{"roughness":.7}})["ok"],"Agent controls material")
    var valid_keys: Variant=doc.state["pieces"][0]["limits_deg"]
    expect(not doc.dispatch({"op":"update_piece","id":"torso","values":{"angle_deg":200}})["ok"] and doc.state["pieces"][0]["limits_deg"]==valid_keys,"Joint limit rejects bad edit")
    expect(doc.dispatch({"op":"set_key","id":"head","time":0,"angle_deg":10})["ok"] and doc.dispatch({"op":"set_key","id":"head","time":1,"angle_deg":30})["ok"],"Build keys incrementally")
    expect(doc.state["tracks"]["head"]==[[0.0,10.0],[1.0,30.0]],"Later pose keeps earlier keys")
    expect(doc.dispatch({"op":"set_key","id":"head","time":1,"angle_deg":20})["ok"] and doc.state["tracks"]["head"]==[[0.0,10.0],[1.0,20.0]],"Replace current key without duplicates")
    var track: Array=doc.state["tracks"]["head"].duplicate(true)
    expect(not doc.dispatch({"op":"set_key","id":"head","time":NAN,"angle_deg":0})["ok"] and not doc.dispatch({"op":"set_key","id":"head","time":1,"angle_deg":200})["ok"] and doc.state["tracks"]["head"]==track,"Reject invalid key atomically")
    if not failed: print("LIE18 DOCUMENT PASS ",checks," acceptance checks")
    quit(1 if failed else 0)
