extends SceneTree
const Lab=preload("res://lie_robot_world_lab.gd")
const Controller=preload("res://lie_robot_controller.gd")
const Rig=preload("res://lie26_rig.gd")
var lab: Node3D
var checks: int=0
var failed: bool=false
var max_stance_drift: float=0
var max_ik_error: float=0
var plant_failure_frames: int=0
func _initialize() -> void:call_deferred("run")
func expect(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;push_error("R2 MOTION: "+label)
func set_motion(position: Vector3,heading: float) -> void:
    expect(lab.command({"op":"set_values","values":{"motion":Controller.initial_motion(position,heading),"playing":false,"move":[0,0],"turn":0}})["ok"],"Restore declared clear start")
    for i in range(2):await physics_frame
func advance(ticks: int,move: Array=[0,1],turn: float=0) -> void:
    expect(lab.command({"op":"set_values","values":{"move":move,"turn":turn}})["ok"],"Shared movement mutation")
    var before: int=lab.state["motion"]["ticks"];var result: Dictionary=lab.command({"op":"advance","ticks":ticks})
    expect(result["ok"] and result["target_tick"]==before+ticks,"Exact asynchronous physics step contract")
    var old_feet: Dictionary=lab.state["motion"]["feet"].duplicate(true)
    for i in range(ticks+10):
        await physics_frame
        var m: Dictionary=lab.state["motion"]
        for side in ["right","left"]:
            var a: Dictionary=old_feet[side];var b: Dictionary=m["feet"][side]
            if not a["swing"] and not b["swing"] and m["walking"]:
                var p: Vector3=Rig.vector(a["target"]);var q: Vector3=Rig.vector(b["target"]);p.y=0;q.y=0;var drift: float=p.distance_to(q)
                max_stance_drift=maxf(max_stance_drift,drift);expect(drift<.00001,"Planted foot stays fixed in world X/Z")
        old_feet=m["feet"].duplicate(true)
        expect(m["position"][1]>-.03,"Gravity and source floor retain support")
        if i%4==0:
            var sample: Dictionary=lab.Assembly.build(lab.effect.catalog,lab.actor.rig_state(m,lab.state["grip"],true))
            for ik in sample["rig"]["ik"].values():
                max_ik_error=maxf(max_ik_error,ik["residual_m"])
                if ik["clamped"] or ik["residual_m"]>.003:plant_failure_frames+=1
                expect(ik["residual_m"]<.003 and not ik["clamped"],"Intermediate foot poses reach across source curb")
        if lab.agent_snapshot()["motion"]["remaining_ticks"]==0:break
    await process_frame
    expect(lab.state["motion"]["ticks"]==before+ticks,"Only requested ticks execute while paused")
    for ik in lab.agent_snapshot()["metrics"]["ik"].values():
        if ik["clamped"] or ik["residual_m"]>=.003:print("R2 IK DIAGNOSTIC ",JSON.stringify({"motion":lab.state["motion"],"ik":ik}))
        max_ik_error=maxf(max_ik_error,ik["residual_m"]);expect(ik["residual_m"]<.003 and not ik["clamped"],"Actual collision pose remains reachable")
func run() -> void:
    lab=Lab.new();root.add_child(lab)
    for i in range(3):await physics_frame
    expect(lab.effect.capture_loaded,"Verified combined bank available")
    expect(lab.validate(lab.state).is_empty(),"Complete initial state validates")
    var decoded: Dictionary=JSON.parse_string(JSON.stringify(lab.state))
    expect(lab.validate(decoded).is_empty() and lab.command({"op":"set_values","values":decoded})["ok"],"Actual JSON number semantics round-trip tick counters")
    expect(not lab.command({"op":"advance","ticks":1.5})["ok"],"Fractional physics ticks reject")
    expect(lab._environment.size()==71,"Original house without roof plus four courtyard tiles")
    var initial: Dictionary=lab.state.duplicate(true);var revision: int=lab.revision
    expect(not lab.command({"op":"set_values","values":{"move":[0,2],"grip":.8}})["ok"],"Invalid movement rejects atomically")
    expect(lab.state==initial and lab.revision==revision,"Rejected state leaves revision untouched")
    await set_motion(Vector3(-1.8,-.018,3.55),180);await advance(240)
    expect(lab.state["motion"]["position"][2]>2.25,"Solid front wall blocks capsule")
    var blocked_position: Array=lab.state["motion"]["position"].duplicate();var blocked_phase: float=lab.state["motion"]["phase"]
    await advance(60)
    expect(Rig.vector(blocked_position).distance_to(Rig.vector(lab.state["motion"]["position"]))<.003,"Blocked controller does not tunnel")
    expect(absf(lab.state["motion"]["phase"]-blocked_phase)<.00001,"Blocked walk does not advance gait phase")
    await set_motion(Vector3(-.6,-.018,3.55),180);await advance(300)
    expect(lab.state["motion"]["position"][2]<-.3 and lab.state["motion"]["position"][2]>-1.4,"Open source doorway admits complete character")
    expect(lab.state["motion"]["grounded"],"Interior floor support")
    await advance(180)
    expect(lab.state["motion"]["position"][2]>-1.46,"Back wall blocks movement")
    await set_motion(Vector3(-.6,.002,0),90);await advance(240)
    expect(lab.state["motion"]["position"][0]<2.06 and lab.state["motion"]["position"][0]>1.9,"East wall stops capsule")
    await set_motion(Vector3(1.8,-.018,3.55),180);await advance(240)
    expect(lab.state["motion"]["position"][2]>2.25,"Window opening does not admit ground-level capsule")
    await set_motion(Vector3(0,.002,0),0)
    var camera: Transform3D=lab.actor.camera_pose(lab.state["motion"],0,15,3.2)
    expect(lab.actor.last_camera_fraction<.85,"Third-person camera retracts at wall")
    var sphere:=SphereShape3D.new();sphere.radius=.12;var query:=PhysicsShapeQueryParameters3D.new();query.shape=sphere;query.transform=camera;query.collision_mask=1;query.exclude=[lab.actor.get_rid()]
    expect(lab.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(),"Retracted camera does not intersect wall")
    var inside: Dictionary=Controller.initial_motion(Vector3(2.472,.002,0),0);var old: Dictionary=lab.state.duplicate(true)
    expect(not lab.command({"op":"set_values","values":{"motion":inside}})["ok"] and lab.state==old,"Restore cannot embed the capsule inside wall")
    await set_motion(Vector3(0,-.018,4.5),0);await advance(180)
    expect(lab.state["motion"]["position"][2]<5.36,"Bounded courtyard prevents falling off test floor")
    var report: Dictionary={"checks":checks,"failed":failed,"max_stance_xz_drift_m":max_stance_drift,"max_ik_error_m":max_ik_error,"plant_failure_frames":plant_failure_frames,"door_passed":not failed,"note":"Actual Godot CharacterBody3D physics against authored collision triangles; no renderer/FPS claim."}
    var file:=FileAccess.open("res://robot-world-motion-verification.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close();print("R2 MOTION ",JSON.stringify(report));root.remove_child(lab);lab.free();await process_frame;quit(1 if failed else 0)
