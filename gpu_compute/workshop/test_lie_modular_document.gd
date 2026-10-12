extends SceneTree
const Doc=preload("res://workshop/lie_modular_document.gd")
var checks: int=0
func expect(ok: bool,message: String) -> void:
    checks+=1
    if not ok:push_error("LIE22 DOCUMENT FAIL: "+message);quit(1)
func _initialize() -> void:
    var d:=Doc.new()
    expect(Doc.connectivity(d.state)["supported"].size()==48,"Initially all masonry is supported")
    expect(d.dispatch({"op":"set_values","values":{"iris_color":[.2,.4,.8],"pupil_radius":.003}})["ok"],"Eye parameters")
    var before: Dictionary=d.snapshot()
    expect(not d.dispatch({"op":"set_values","values":{"pupil_radius":.02}})["ok"] and d.snapshot()==before,"Invalid pupil leaves state atomic")
    expect(not d.dispatch({"op":"set_values","values":{"iris_color":[NAN,0,1]}})["ok"] and d.snapshot()==before,"Nonfinite color")
    expect(not d.dispatch({"op":"strike","cell":48})["ok"],"Cell bounds")
    expect(not d.dispatch({"op":"strike","cell":2.5})["ok"],"Integer cell")
    expect(not d.dispatch({"op":"set_values","values":{"seed":1.5}})["ok"],"Integer seed")
    expect(not d.dispatch({"op":"set_values","values":{"damage":[]}})["ok"],"Damage is command-only")
    expect(not d.dispatch({"op":"set_values","expected_revision":999,"values":{"coating":false}})["ok"],"Agent revision lease")
    expect(not d.dispatch({"op":"batch","commands":[{"op":"strike","cell":27},{"op":"set_values","values":{"mode":"bad"}}]})["ok"] and d.snapshot()==before,"Invalid batch is atomic")
    expect(d.dispatch({"op":"strike","cell":27,"energy":40})["ok"] and Doc.connectivity(d.state)["removed"].is_empty(),"Subthreshold damage")
    expect(d.dispatch({"op":"strike","cell":27,"energy":60})["ok"] and Doc.connectivity(d.state)["removed"]==[27],"Cumulative fracture")
    expect(Doc.connectivity(d.state)["unsupported"].is_empty(),"Single hole retains alternate support")
    expect(d.dispatch({"op":"undo"})["ok"] and d.state["damage"][27]==40,"Undo damage")
    expect(d.dispatch({"op":"redo"})["ok"] and d.state["damage"][27]==100,"Redo damage")
    expect(d.dispatch({"op":"save_document"})["ok"],"Save shared document")
    expect(d.dispatch({"op":"reset_wall"})["ok"] and Doc.connectivity(d.state)["removed"].is_empty(),"Reset wall")
    expect(d.dispatch({"op":"load_document"})["ok"] and d.state["damage"][27]==100,"Reload damage and appearance")
    var batch: Array=[]
    for col in range(Doc.COLS):batch.append({"op":"strike","cell":col})
    expect(d.dispatch({"op":"batch","commands":batch})["ok"],"Remove foundation in one transaction")
    expect(Doc.connectivity(d.state)["unsupported"].size()==41,"Disconnected upper wall is unsupported")
    expect(d.dispatch({"op":"reset_wall"})["ok"] and Doc.connectivity(d.state)["supported"].size()==48,"Restore foundation and connectivity")
    print("LIE22 DOCUMENT PASS ",checks," checks");quit(0)
