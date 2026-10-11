extends SceneTree
const Doc=preload("res://workshop/lie_face_document.gd")
var checks: int=0
var failed: bool=false
func expect(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;push_error("LIE23 DOCUMENT FAIL: "+label)
func _initialize() -> void:
    var d:=Doc.new();expect(d.validate(d.state)=="","Default open-face contract")
    expect(d.dispatch({"op":"set_values","values":{"blink":.5,"iris_color":[.2,.6,.3],"skin_tint":[.6,.4,.3]}})["ok"],"Skin, iris and lids share command")
    var before: Dictionary=d.snapshot()
    for value in [NAN,INF,-.01,1.01,"1",true]:
        expect(not d.dispatch({"op":"set_values","values":{"head_yaw":15,"blink":value}})["ok"] and d.snapshot()==before,"Invalid blink rejected atomically")
    expect(not d.dispatch({"op":"set_values","values":{"iris_color":[1,1,NAN],"head_yaw":10}})["ok"] and d.snapshot()==before,"Invalid iris preserves all state")
    expect(not d.dispatch({"op":"set_values","values":{"skin_tint":[2,0,0]}})["ok"],"Tint bounded")
    expect(not d.dispatch({"op":"set_values","values":{"framing":"invalid"}})["ok"],"Framing enum")
    expect(not d.dispatch({"op":"set_values","values":{"pupil_radius":.0001}})["ok"],"Pupil physical size range")
    var revision: int=d.revision
    expect(d.dispatch(JSON.parse_string(JSON.stringify({"op":"set_values","expected_revision":revision,"values":{"gaze_yaw":20}})))["ok"],"JSON numeric revision")
    expect(not d.dispatch({"op":"set_values","expected_revision":revision,"values":{"gaze_yaw":-20}})["ok"],"Stale revision rejected")
    expect(d.dispatch({"op":"undo"})["ok"] and d.state["gaze_yaw"]==0,"Undo gaze")
    expect(d.dispatch({"op":"redo"})["ok"] and d.state["gaze_yaw"]==20,"Redo gaze")
    expect(d.dispatch({"op":"save_document"})["ok"],"Save shared state")
    d.dispatch({"op":"set_values","values":{"iris_color":[1,0,0]}})
    expect(d.dispatch({"op":"load_document"})["ok"] and d.state["iris_color"]==[.2,.6,.3],"Open restores canonical colors")
    expect(d.dispatch({"op":"set_playing","value":true})["ok"] and d.dispatch({"op":"set_time","value":1.875})["ok"] and d.evaluated()["blink"]>.999,"Authored playback closes lids")
    expect(d.state["blink"]==.5,"Playback preserves authored blink slider")
    d.dispatch({"op":"set_time","value":0});expect(d.evaluated()["blink"]==.5,"Playback outside blink pulse")
    expect(not d.dispatch({"op":"set_time","value":4.01})["ok"],"Playback time bounded")
    expect(not d.dispatch({"op":"set_values","values":{"unknown":1}})["ok"],"Unknown field rejected")
    print("LIE23 DOCUMENT ","FAIL" if failed else "PASS"," ",checks," checks");quit(1 if failed else 0)
