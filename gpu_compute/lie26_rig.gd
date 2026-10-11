extends RefCounted
# Shared semantic rig: exact rigid interiors, limited hinges, two-link IK.
const LIMITS={"root_yaw":[-180,180],"torso_bend":[-25,35],"torso_twist":[-45,45],"head_yaw":[-70,70],"head_pitch":[-35,35],
    "right_shoulder":[-45,130],"left_shoulder":[-45,130],"right_abduction":[0,120],"left_abduction":[0,120],
    "right_elbow":[0,140],"left_elbow":[0,140],"right_wrist":[-45,60],"left_wrist":[-45,60],
    "right_hip":[-35,100],"left_hip":[-35,100],"right_knee":[0,140],"left_knee":[0,140],"right_ankle":[-30,40],"left_ankle":[-30,40]}
const CHAINS={"right_hand":[3,4,5,-1],"left_hand":[6,7,8,-1],"right_foot":[9,10,11,1],"left_foot":[12,13,14,1]}

static func vector(v: Array) -> Vector3:return Vector3(v[0],v[1],v[2])
static func array(v: Vector3) -> Array:return [v.x,v.y,v.z]

static func valid_vector(v: Variant,bound: float=4.0) -> bool:
    if not v is Array or v.size()!=3:return false
    for x in v:
        if not (x is int or x is float) or not is_finite(float(x)) or absf(x)>bound:return false
    return true

static func validate_pose(pose: Variant) -> bool:
    if not pose is Dictionary:return false
    for key in pose:
        var v: Variant=pose[key]
        if key=="root_position":
            if not valid_vector(v):return false
        elif not LIMITS.has(key) or not (v is int or v is float) or not is_finite(float(v)) or v<LIMITS[key][0] or v>LIMITS[key][1]:return false
    return true

static func validate_targets(targets: Variant) -> bool:
    if not targets is Dictionary:return false
    for key in targets:
        var v: Variant=targets[key]
        if not CHAINS.has(key) or not v is Dictionary or not valid_vector(v.get("position")) or not valid_vector(v.get("pole")) or not v.get("enabled",true) is bool:return false
        for field in v:
            if field not in ["position","pole","enabled"]:return false
    return true

static func local_rotation(name: String,pose: Dictionary) -> Quaternion:
    var x: float=0;var y: float=0;var z: float=0
    if name=="pelvis":y=pose.get("root_yaw",0)
    elif name=="torso":x=-pose.get("torso_bend",0);y=pose.get("torso_twist",0)
    elif name=="head":x=-pose.get("head_pitch",0);y=pose.get("head_yaw",0)
    else:
        var side: String=name.get_slice("_",0);var sign: float=-1 if side=="right" else 1
        if name.ends_with("upper_arm"):x=-pose.get(side+"_shoulder",0);z=sign*float(pose.get(side+"_abduction",0))
        elif name.ends_with("forearm"):x=-pose.get(side+"_elbow",0)
        elif name.ends_with("hand"):x=-pose.get(side+"_wrist",0)
        elif name.ends_with("thigh"):x=-pose.get(side+"_hip",0)
        elif name.ends_with("shin"):x=pose.get(side+"_knee",0)
        elif name.ends_with("foot"):x=-pose.get(side+"_ankle",0)
    return Quaternion(Vector3.UP,deg_to_rad(y))*Quaternion(Vector3.BACK,deg_to_rad(z))*Quaternion(Vector3.RIGHT,deg_to_rad(x))

static func fk(bones: Array,pose: Dictionary,overrides: Dictionary={}) -> Dictionary:
    var rotations: Array[Quaternion]=[];var origins: Array[Vector3]=[];var locals: Array[Quaternion]=[];var skins: Array[Transform3D]=[]
    for i in range(bones.size()):
        var b: Dictionary=bones[i];var parent: int=int(b["parent"]);var pivot: Vector3=vector(b["pivot"])
        var local: Quaternion=overrides.get(i,local_rotation(b["name"],pose));locals.append(local)
        var rotation: Quaternion=local if parent<0 else rotations[parent]*local
        var origin: Vector3=pivot+vector(pose.get("root_position",[0,0,0])) if parent<0 else origins[parent]+rotations[parent]*(pivot-vector(bones[parent]["pivot"]))
        rotations.append(rotation);origins.append(origin);skins.append(Transform3D(Basis(rotation),origin-rotation*pivot))
    return {"rotations":rotations,"origins":origins,"locals":locals,"skins":skins}

static func evaluate(bones: Array,pose: Dictionary,targets: Dictionary={}) -> Dictionary:
    var overrides: Dictionary={};var report: Dictionary={};var result: Dictionary=fk(bones,pose)
    for key in targets:
        var target: Dictionary=targets[key]
        if not target.get("enabled",true):continue
        var chain: Array=CHAINS[key];var upper: int=chain[0];var lower: int=chain[1];var tip: int=chain[2];var parent: int=int(bones[upper]["parent"])
        var qparent: Quaternion=result["rotations"][parent];var root: Vector3=result["origins"][upper]
        var requested: Vector3=vector(target["position"]);var local_goal: Vector3=qparent.inverse()*(requested-root)
        var a: Vector3=vector(bones[lower]["pivot"])-vector(bones[upper]["pivot"])
        var b: Vector3=vector(bones[tip]["pivot"])-vector(bones[lower]["pivot"])
        var sign: float=chain[3];var low: float=0;var high: float=deg_to_rad(140)
        var maximum: float=(a+b).length();var minimum: float=(a+Quaternion(Vector3.RIGHT,sign*high)*b).length()
        var wanted: float=clampf(local_goal.length(),minimum,maximum)
        # Monotonic hinge distance search retains the source's oblique rest
        # axes rather than assuming two perfectly collinear abstract bones.
        for _i in range(28):
            var mid: float=(low+high)*.5
            if (a+Quaternion(Vector3.RIGHT,sign*mid)*b).length()>wanted:low=mid
            else:high=mid
        var hinge: Quaternion=Quaternion(Vector3.RIGHT,sign*(low+high)*.5)
        var rest_tip: Vector3=a+hinge*b
        var direction: Vector3=local_goal.normalized() if local_goal.length()>.00001 else rest_tip.normalized()
        var ball: Quaternion=Quaternion(rest_tip.normalized(),direction)
        var pole: Vector3=qparent.inverse()*(vector(target["pole"])-root)
        var current: Vector3=ball*a;current-=direction*current.dot(direction)
        var desired: Vector3=pole-direction*pole.dot(direction)
        if current.length()>.00001 and desired.length()>.00001:
            var twist: float=atan2(direction.dot(current.cross(desired)),current.dot(desired))
            ball=Quaternion(direction,twist)*ball
        # Ball limit is a conservative game-rig cone, not a medical ROM table.
        var angle: float=ball.get_angle()
        if angle>PI:ball=-ball;angle=ball.get_angle()
        if angle>deg_to_rad(160):ball=Quaternion.IDENTITY.slerp(ball,deg_to_rad(160)/angle)
        overrides[upper]=ball;overrides[lower]=hinge;result=fk(bones,pose,overrides)
        if key.ends_with("foot"):
            overrides[tip]=result["rotations"][lower].inverse();result=fk(bones,pose,overrides)
        var actual: Vector3=result["origins"][tip]
        report[key]={"requested":array(requested),"actual":array(actual),"residual_m":actual.distance_to(requested),"hinge_deg":rad_to_deg((low+high)*.5),"clamped":absf(wanted-local_goal.length())>.00001 or angle>deg_to_rad(160)}
    result["ik"]=report
    return result

static func packet(evaluated: Dictionary) -> PackedByteArray:
    var data:=PackedFloat32Array()
    for t in evaluated["skins"]:
        var q: Quaternion=t.basis.get_rotation_quaternion();var p: Vector3=t.origin
        # Quaternion product (translation,0)*q, divided by two.
        var dxyz: Vector3=(p*q.w+p.cross(Vector3(q.x,q.y,q.z)))*.5;var dw: float=-p.dot(Vector3(q.x,q.y,q.z))*.5
        data.append_array(PackedFloat32Array([q.x,q.y,q.z,q.w,dxyz.x,dxyz.y,dxyz.z,dw]))
    return data.to_byte_array()

static func sample_position(sample: PackedFloat32Array,offset: int,skins: Array,vertices: PackedFloat32Array=PackedFloat32Array(),triangles: PackedInt32Array=PackedInt32Array()) -> Vector3:
    if sample[offset+3]<0:
        var ti: int=int(-sample[offset+3])-1;var p:=Vector3.ZERO
        for corner in range(3):
            var vi: int=triangles[ti*4+corner]*24
            var vertex:=PackedFloat32Array();vertex.resize(20)
            for axis in range(3):vertex[axis]=vertices[vi+axis]
            vertex[3]=vertices[vi+3];vertex[14]=vertices[vi+4];vertex[13]=vertices[vi+5]
            p+=sample_position(vertex,0,skins)*sample[offset+corner]
        return p
    var a: Transform3D=skins[int(sample[offset+3])];var b: Transform3D=skins[int(sample[offset+14])];var w: float=sample[offset+13]
    var qa: Quaternion=a.basis.get_rotation_quaternion();var qb: Quaternion=b.basis.get_rotation_quaternion()
    var da:=Quaternion(a.origin.x,a.origin.y,a.origin.z,0)*qa*.5;var db:=Quaternion(b.origin.x,b.origin.y,b.origin.z,0)*qb*.5
    if qa.dot(qb)<0:qb=-qb;db=-db
    var q: Quaternion=qa*(1-w)+qb*w;var d: Quaternion=da*(1-w)+db*w;var norm: float=q.length();q/=norm;d/=norm
    var t: Quaternion=d*q.inverse()*2
    return q*Vector3(sample[offset],sample[offset+1],sample[offset+2])+Vector3(t.x,t.y,t.z)

static func walk(time: float) -> Dictionary:
    var pose: Dictionary={"root_position":[0,-.03+.008*cos(time*TAU*2),0],"torso_bend":4,"head_yaw":8*sin(time*TAU*.5)}
    var targets: Dictionary={}
    for side in ["right","left"]:
        var phase: float=time*TAU+(0 if side=="right" else PI);var sign: float=-1 if side=="right" else 1
        pose[side+"_shoulder"]=18*sin(phase);pose[side+"_elbow"]=20+10*cos(phase)
        targets[side+"_foot"]={"position":[sign*.075,.068+.09*maxf(sin(phase),0),.06+.16*cos(phase)],"pole":[sign*.075,.45,1.0]}
    return {"pose":pose,"targets":targets}
