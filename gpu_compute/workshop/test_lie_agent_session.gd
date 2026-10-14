extends SceneTree
const Session=preload("res://workshop/lie_agent_session.gd")
class TestSession extends "res://workshop/lie_agent_session.gd":
    var shutdown_seen: bool=false
    func _shutdown_session() -> void:shutdown_seen=true
const Lab=preload("res://lie27_regions_lab.gd")
var checks: int=0
var failed: bool=false
func check(ok: bool,message: String) -> void:
    checks+=1
    if not ok:failed=true;push_error(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var lab:=Lab.new();var agent:=TestSession.new();root.add_child(agent)
    agent.target_override=lab;agent.lab_override="lie27"
    var directory: String=OS.get_user_data_dir()+"/agent-test-"+str(OS.get_process_id())
    check(agent.initialize(directory)["ok"],"Live protocol initializes without a GPU")
    check(agent.snapshot()["capabilities"]["fields"].size()==lab.state.size(),"Every current control is discoverable")
    check(agent.snapshot()["capabilities"]["face_keys"].size()==7 and agent.snapshot()["capabilities"]["pose_limits"].has("right_index"),"Facial and digit ranges exposed")
    var initial: Dictionary=lab.state.duplicate(true)
    check((await agent.dispatch({"op":"set_values","values":{"brows":false},"expected_revision":0}))["ok"],"Agent changes use actual laboratory command")
    check(lab.state["brows"]==false and lab.revision==1,"Laboratory owns state and revision")
    check(not (await agent.dispatch({"op":"set_values","values":{"brows":true,"light_power":0},"expected_revision":0}))["ok"] and lab.state["light_power"]==70,"Stale revision changes nothing")
    check(not (await agent.dispatch({"op":"set_values","values":{"brows":1,"light_power":0}}))["ok"] and lab.state["light_power"]==70,"Invalid control transaction is atomic")
    check(not (await agent.dispatch({"op":"set_values","values":{"brows":true},"expected_session":"old"}))["ok"],"Stale process session rejected")
    check(not (await agent.dispatch({"op":"set_values","values":{"brows":true},"expected_lab":"lie26"}))["ok"],"Wrong laboratory rejected")
    check((await agent.dispatch({"op":"save_state"}))["ok"],"State saved atomically")
    check((await agent.dispatch({"op":"set_values","values":{"brows":true}}))["ok"],"State changes after save")
    check((await agent.dispatch({"op":"load_state"}))["ok"] and lab.state["brows"]==false,"Saved controls restore through same validation")
    check(not (await agent.dispatch({"op":"save_state","filename":"../escape.lie.json"}))["ok"],"State filename cannot escape session directory")
    var revision: int=lab.revision
    agent._write_json(directory+"/bad.lie.json",{"schema":1,"lab":"lie26","state":initial})
    check(not (await agent.dispatch({"op":"load_state","filename":"bad.lie.json"}))["ok"] and lab.revision==revision,"Wrong saved lab cannot overwrite controls")
    agent._write_json(directory+"/bad.lie.json",{"schema":1,"lab":"lie27","state":{"brows":true}})
    check(not (await agent.dispatch({"op":"load_state","filename":"bad.lie.json"}))["ok"] and lab.revision==revision,"Incomplete save cannot partly restore")
    var corrupt: Dictionary=initial.duplicate(true);corrupt["brows"]=1
    agent._write_json(directory+"/bad.lie.json",{"schema":1,"lab":"lie27","state":corrupt})
    check(not (await agent.dispatch({"op":"load_state","filename":"bad.lie.json"}))["ok"] and lab.revision==revision,"Invalid persisted control is atomic")
    check(not (await agent.dispatch({"op":"capture"}))["ok"],"No GPU capture is reported as successful")
    check(not (await agent.dispatch({"op":"open_lab","lab":"../../other"}))["ok"],"Navigation uses declared laboratories only")
    agent._write_json(directory+"/inbox.json",{"request_id":"external-test","request":{"op":"set_pose","values":{"right_index":25},"expected_revision":lab.revision}})
    agent._process(.3)
    for i in range(5):await process_frame
    var response: Variant=agent._read_json(directory+"/outbox.json")
    check(response is Dictionary and response["request_id"]=="external-test" and response["result"]["ok"] and lab.state["pose"]["right_index"]==25,"File inbox reaches actual digit command and correlates response")
    check(not FileAccess.file_exists(directory+"/inbox.json") and response["snapshot"]["revision"]==lab.revision,"Consumed request publishes current state")
    check(agent.capabilities()["operations"].has("shutdown"),"Session lifetime operation discoverable")
    check(not (await agent.dispatch({"op":"shutdown"}))["ok"] and not agent._shutdown_pending,"Missing identity cannot close a process")
    check(not (await agent.dispatch({"op":"shutdown","expected_session":"old"}))["ok"] and not agent._shutdown_pending,"Stale identity cannot close this process")
    check((await agent.dispatch({"op":"shutdown","expected_session":agent.session_id}))["ok"],"Exact session accepts orderly close")
    await process_frame
    check(agent.shutdown_seen and not (await agent.dispatch({"op":"shutdown","expected_session":agent.session_id}))["ok"],"Close callback runs once; duplicate close rejected")
    lab.free();agent.queue_free();await process_frame
    print("LIE AGENT SESSION ","FAIL" if failed else "PASS"," ",checks," checks");quit(1 if failed else 0)
