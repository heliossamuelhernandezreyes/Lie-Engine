extends CharacterBody3D
## Collision movement produces targets; lie26_rig remains the only bone solver.
const Rig=preload("res://lie26_rig.gd")
const STRIDE=.60
const RADIUS=.35
const HEIGHT=1.76
var last_contacts: Array=[]
var last_camera_fraction: float=1.0
var _capsule: CapsuleShape3D
func _ready() -> void:
    collision_layer=2;collision_mask=5;safe_margin=.002;floor_snap_length=.08
    var shape:=CapsuleShape3D.new();shape.radius=RADIUS;shape.height=HEIGHT;_capsule=shape
    var collider:=CollisionShape3D.new();collider.shape=shape;collider.position.y=HEIGHT*.5;add_child(collider)
static func initial_motion(position: Vector3=Vector3(-.6,-.018,3.55),heading: float=180.0) -> Dictionary:
    var basis:=Basis(Vector3.UP,deg_to_rad(heading));var feet: Dictionary={}
    for side in ["right","left"]:
        var sign: float=-1 if side=="right" else 1;var foot: Array=Rig.array(position+basis*Vector3(sign*.135,.103,.045))
        feet[side]={"phase":0.0 if side=="right" else .5,"swing":false,"plant":foot,"start":foot,"end":foot,"target":foot}
    return {"position":Rig.array(position),"heading":heading,"velocity":[0,0,0],"phase":0.0,"travel":0.0,"speed":0.0,"grounded":false,"walking":false,"blend":0.0,"ticks":0,"feet":feet}
func restore(motion: Dictionary) -> void:
    global_position=Rig.vector(motion["position"]);velocity=Rig.vector(motion["velocity"]);last_contacts=[]
func overlaps_world(point: Vector3) -> bool:
    var shape:=CapsuleShape3D.new();shape.radius=RADIUS-.006;shape.height=HEIGHT-.012
    var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,point+Vector3(0,HEIGHT*.5,0));query.collision_mask=5;query.exclude=[get_rid()]
    return not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
func floor_height(point: Vector3) -> float:
    var top:=Vector3(point.x,global_position.y+.15,point.z);var bottom:=Vector3(point.x,global_position.y-.20,point.z)
    var query:=PhysicsRayQueryParameters3D.create(top,bottom,1,[get_rid()])
    var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
    if not hit.is_empty() and hit["normal"].y>.7 and absf(hit["position"].y-global_position.y)<.06:return float(hit["position"].y)
    return global_position.y-safe_margin
func landing(point: Vector3) -> Vector3:
    point.y=floor_height(point)+.105;return point
func future_landing(side: float,basis: Basis,direction: Vector3) -> Vector3:
    # The source floor has a 20 mm threshold. Raise the forecast 60 mm so
    # it does not mistake that walkable curb for an impassable wall.
    var query:=PhysicsShapeQueryParameters3D.new();query.shape=_capsule;query.transform=Transform3D(Basis.IDENTITY,global_position+Vector3(0,HEIGHT*.5+.06,0));query.motion=direction*(STRIDE*.75);query.collision_mask=5;query.exclude=[get_rid()]
    var safe: PackedFloat32Array=get_world_3d().direct_space_state.cast_motion(query)
    return landing(global_position+basis*Vector3(side*.135,0,0)+query.motion*maxf(safe[0]-.015,0))
func step(motion: Dictionary,input: Vector2,turn: float,speed: float,delta: float) -> void:
    var before: Vector3=global_position;motion["heading"]=wrapf(motion["heading"]+turn*100*delta,-180,180)
    var basis:=Basis(Vector3.UP,deg_to_rad(motion["heading"]));var desired: Vector3=basis*Vector3(input.x,0,input.y).limit_length(1)*speed
    velocity.x=move_toward(velocity.x,desired.x,3.5*delta);velocity.z=move_toward(velocity.z,desired.z,3.5*delta)
    velocity.y=-.3 if is_on_floor() else maxf(velocity.y-9.8*delta,-12)
    move_and_slide();var distance: Vector3=global_position-before;distance.y=0
    var amount: float=distance.length();var walking: bool=amount/delta>.025
    motion["speed"]=amount/delta;motion["travel"]+=amount;motion["ticks"]+=1;motion["grounded"]=is_on_floor()
    motion["blend"]=move_toward(motion["blend"],1.0 if walking else 0.0,delta*5)
    var direction: Vector3=distance.normalized() if walking else basis*Vector3.BACK
    if walking:motion["phase"]=fmod(motion["phase"]+amount/STRIDE,1.0)
    for side in ["right","left"]:
        var f: Dictionary=motion["feet"][side];var phase: float=fmod(motion["phase"]+(0.0 if side=="right" else .5),1.0);var sign: float=-1 if side=="right" else 1
        if walking:
            var swinging: bool=phase>=.5
            if swinging and (not f["swing"] or not motion["walking"]):
                f["start"]=f["target"].duplicate();f["end"]=Rig.array(future_landing(sign,basis,direction))
            elif not swinging and f["swing"]:f["plant"]=f["end"].duplicate()
            if swinging:
                var t: float=(phase-.5)*2;var ease: float=t*t*(3-2*t);var target: Vector3=Rig.vector(f["start"]).lerp(Rig.vector(f["end"]),ease);target.y+=sin(PI*t)*.065;f["target"]=Rig.array(target)
            else:f["target"]=f["plant"].duplicate()
            f["swing"]=swinging
        else:
            # Finish lowering the lifted foot without dragging planted X/Z anchors.
            var target: Vector3=Rig.vector(f["target"]);target.y=move_toward(target.y,floor_height(target)+.105,delta*.3);f["target"]=Rig.array(target);f["plant"]=f["target"].duplicate()
        f["phase"]=phase
    motion["walking"]=walking;motion["position"]=Rig.array(global_position);motion["velocity"]=Rig.array(velocity)
    last_contacts=[]
    for i in range(get_slide_collision_count()):
        var c: KinematicCollision3D=get_slide_collision(i);last_contacts.append({"normal":Rig.array(c.get_normal()),"point":Rig.array(c.get_position()),"body":str(c.get_collider().name)})
func rig_state(motion: Dictionary,grip: float,cables: bool) -> Dictionary:
    var phase: float=motion["phase"]*TAU;var blend: float=motion["blend"];var basis:=Basis(Vector3.UP,deg_to_rad(motion["heading"]));var origin: Vector3=Rig.vector(motion["position"])
    var pose: Dictionary={"root_position":[0,-.055+.004*cos(phase*2)*blend,0],"torso_bend":3*blend,"torso_twist":3*sin(phase)*blend,"right_abduction":3,"left_abduction":3,
        "right_shoulder":18*sin(phase)*blend,"left_shoulder":-18*sin(phase)*blend,"right_elbow":20+6*cos(phase)*blend,"left_elbow":20-6*cos(phase)*blend}
    var targets: Dictionary={}
    for side in ["right","left"]:
        var sign: float=-1 if side=="right" else 1;var local: Vector3=basis.inverse()*(Rig.vector(motion["feet"][side]["target"])-origin)
        targets[side+"_foot"]={"position":Rig.array(local),"pole":[sign*.135,.45,1]}
    return {"mode":"manual","time":0.0,"pose":pose,"targets":targets,"foot_ik":true,"focus":"body","floor":false,"grip":grip,"cables":cables}
func camera_pose(motion: Dictionary,yaw: float,elevation: float,distance: float) -> Transform3D:
    var target: Vector3=Rig.vector(motion["position"])+Vector3(0,1.18,0);var a: float=deg_to_rad(motion["heading"]+180+yaw);var e: float=deg_to_rad(elevation)
    var offset:=Vector3(sin(a)*cos(e),sin(e),cos(a)*cos(e))*distance
    var sphere:=SphereShape3D.new();sphere.radius=.14
    var query:=PhysicsShapeQueryParameters3D.new();query.shape=sphere;query.transform=Transform3D(Basis.IDENTITY,target);query.motion=offset;query.collision_mask=1;query.exclude=[get_rid()]
    var result: PackedFloat32Array=get_world_3d().direct_space_state.cast_motion(query);last_camera_fraction=result[0]
    var position: Vector3=target+offset*maxf(last_camera_fraction-.015,.04)
    return Transform3D(Basis.IDENTITY,position).looking_at(target,Vector3.UP)
