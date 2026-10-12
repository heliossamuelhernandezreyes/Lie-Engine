extends RefCounted
## The existing semantic FK/IK rig owns all rigid poses. Cables follow its anchors.
const Rig=preload("res://lie26_rig.gd")
const CURVE_POINTS=16

static func basis_for(direction: Vector3) -> Basis:
    var y: Vector3=direction.normalized();var helper:=Vector3.FORWARD if absf(y.z)<.9 else Vector3.RIGHT
    var x: Vector3=y.cross(helper).normalized();var z: Vector3=x.cross(y).normalized();return Basis(x,y,z)
static func frame(bones: Dictionary,bone: int) -> Transform3D:return Transform3D(Basis(bones["rotations"][bone]),bones["origins"][bone])
static func add(list: Array,master: String,pose: Transform3D,bone: int=-1,emission: float=.20) -> void:
    list.append({"master":master,"pose":pose,"bone":bone,"curve":-1,"radius_scale":1.0,"emission":emission})
static func piece(list: Array,bones: Dictionary,master: String,bone: int,offset: Vector3,scale: Vector3,rotation: Vector3=Vector3.ZERO,emission: float=.20) -> void:
    add(list,master,frame(bones,bone)*Transform3D(Basis.from_euler(rotation).scaled_local(scale),offset),bone,emission)
static func link(list: Array,master: String,a: Vector3,b: Vector3,radius: float,bone: int) -> void:
    var length: float=a.distance_to(b)
    add(list,master,Transform3D(basis_for(b-a).scaled_local(Vector3(radius,length/.5,radius)),(a+b)*.5),bone,0)
static func anchored(bones: Dictionary,bone: int,offset: Vector3) -> Vector3:return frame(bones,bone)*offset

static func guide(a: Vector3,b: Vector3,bow: Vector3,height: float) -> Array[Vector3]:
    var points: Array[Vector3]=[];var control: Vector3=(a+b)*.5+bow.normalized()*height
    for i in range(129):
        var t: float=float(i)/128;points.append(a*(1-t)*(1-t)+control*2*t*(1-t)+b*t*t)
    return points
static func path_length(points: Array[Vector3]) -> float:
    var result: float=0
    for i in range(1,points.size()):result+=points[i].distance_to(points[i-1])
    return result
static func cable_path(a: Vector3,b: Vector3,bow: Vector3,rest: float) -> Dictionary:
    var requested: float=rest;rest=maxf(rest,a.distance_to(b)*1.002)
    var low: float=0;var high: float=rest*1.6
    for i in range(24):
        var mid: float=(low+high)*.5
        if path_length(guide(a,b,bow,mid))<rest:low=mid
        else:high=mid
    var dense: Array[Vector3]=guide(a,b,bow,(low+high)*.5);var lengths: Array[float]=[0.0]
    for i in range(1,dense.size()):lengths.append(lengths[-1]+dense[i].distance_to(dense[i-1]))
    var total: float=lengths[-1];var sampled: Array[Vector3]=[];var index: int=0
    for i in range(CURVE_POINTS):
        var distance: float=total*float(i)/(CURVE_POINTS-1)
        while index<dense.size()-2 and lengths[index+1]<distance:index+=1
        sampled.append(dense[index].lerp(dense[index+1],(distance-lengths[index])/maxf(lengths[index+1]-lengths[index],.000001)))
    var packet:=PackedFloat32Array();var normal:=Vector3.RIGHT;var previous:=Vector3.UP
    for i in range(CURVE_POINTS):
        var tangent: Vector3=(sampled[mini(i+1,CURVE_POINTS-1)]-sampled[maxi(i-1,0)]).normalized()
        if i==0:
            var helper:=Vector3.RIGHT if absf(tangent.x)<.8 else Vector3.FORWARD;normal=(helper-tangent*helper.dot(tangent)).normalized()
        else:
            normal=Quaternion(previous,tangent)*normal;normal=(normal-tangent*normal.dot(tangent)).normalized()
        previous=tangent;var p: Vector3=sampled[i]
        packet.append_array(PackedFloat32Array([p.x,p.y,p.z,float(i)/(CURVE_POINTS-1),normal.x,normal.y,normal.z,0,tangent.x,tangent.y,tangent.z,total]))
    return {"packet":packet,"requested_length":requested,"length":total,"clamped":rest>requested+.0001,"endpoints":[Rig.array(a),Rig.array(b)]}
static func cable_position(local: Vector3,packet: PackedFloat32Array,curve: int,radius: float=1.0) -> Vector3:
    var value: float=clampf(local.y*2+.5,0,1)*15;var k: int=mini(int(value),14);var f: float=value-k;var a: int=(curve*16+k)*12;var b: int=a+12
    var c0:=Vector3(packet[a],packet[a+1],packet[a+2]);var c1:=Vector3(packet[b],packet[b+1],packet[b+2]);var t0:=Vector3(packet[a+8],packet[a+9],packet[a+10]);var t1:=Vector3(packet[b+8],packet[b+9],packet[b+10]);var step: float=packet[a+11]/15
    var f2: float=f*f;var f3: float=f2*f
    var center: Vector3=c0*(2*f3-3*f2+1)+t0*step*(f3-2*f2+f)+c1*(-2*f3+3*f2)+t1*step*(f3-f2)
    var tangent: Vector3=t0.lerp(t1,f).normalized();var n0:=Vector3(packet[a+4],packet[a+5],packet[a+6]);var n1:=Vector3(packet[b+4],packet[b+5],packet[b+6]);var normal: Vector3=n0.lerp(n1,f);normal=(normal-tangent*normal.dot(tangent)).normalized()
    return center+normal*local.x*radius+normal.cross(tangent)*local.z*radius
static func cable_jacobian(local: Vector3,packet: PackedFloat32Array,curve: int,radius: float=1.0) -> Basis:
    var epsilon: float=.0003;var p: Vector3=cable_position(local,packet,curve,radius)
    var x: Vector3=(cable_position(local+Vector3(epsilon,0,0),packet,curve,radius)-p)/epsilon
    var z: Vector3=(cable_position(local+Vector3(0,0,epsilon),packet,curve,radius)-p)/epsilon
    var low: float=maxf(-.25,local.y-epsilon);var high: float=minf(.25,local.y+epsilon)
    var y: Vector3=(cable_position(Vector3(local.x,high,local.z),packet,curve,radius)-cable_position(Vector3(local.x,low,local.z),packet,curve,radius))/maxf(high-low,.00001)
    return Basis(x,y,z)

static func build(catalog: Dictionary,state: Dictionary) -> Dictionary:
    var pose: Dictionary=state["pose"].duplicate(true);var targets: Dictionary=state["targets"].duplicate(true);var time: float=state["time"]
    if state["mode"]=="walk":
        var phase: float=time*TAU
        pose.merge({"torso_bend":4,"torso_twist":4*sin(phase),"head_yaw":5*sin(phase*.5),"root_position":[0,-.035+.005*cos(phase*2),0]},true)
        for side in ["right","left"]:
            var p: float=phase+(0 if side=="right" else PI);var sign: float=-1 if side=="right" else 1
            pose[side+"_shoulder"]=20*sin(p);pose[side+"_elbow"]=24+9*cos(p);pose[side+"_abduction"]=7
            targets[side+"_foot"]={"position":[sign*.135,.105+.075*maxf(sin(p),0),.045+.16*cos(p)],"pole":[sign*.135,.5,1.0]}
    elif state["mode"]=="reach":pose.merge({"right_shoulder":95,"right_elbow":60,"right_wrist":-20,"torso_twist":-12,"head_yaw":-20},true)
    if state["foot_ik"] and state["mode"]!="walk":
        for side in ["right","left"]:
            if not targets.has(side+"_foot"):
                var sign: float=-1 if side=="right" else 1;targets[side+"_foot"]={"position":[sign*.135,.105,.045],"pole":[sign*.135,.5,1.0]}
    var evaluated: Dictionary=Rig.evaluate(catalog["rig"],pose,targets);var list: Array=[];var origins: Array=evaluated["origins"]
    # Torso / pelvis / helmet: repeated source armor, exposed support frames.
    for sign in [-1,1]:
        piece(list,evaluated,"plate_flat",1,Vector3(sign*.098,.245,.098),Vector3(.88,.98,1.05),Vector3(0,sign*.15,-sign*.11))
        piece(list,evaluated,"plate_shell",1,Vector3(sign*.12,.245,-.068),Vector3(1,1.13,1),Vector3(0,PI,0))
        link(list,"shaft",anchored(evaluated,0,Vector3(sign*.13,.03,0)),anchored(evaluated,1,Vector3(sign*.13,.32,0)),1.05,1)
    piece(list,evaluated,"plate_bracket",1,Vector3(0,.255,.12),Vector3(.60,1.05,.70))
    piece(list,evaluated,"plate_flat",1,Vector3(0,.035,.06),Vector3(.72,.45,.9))
    piece(list,evaluated,"joint",0,Vector3(0,.03,0),Vector3(1.45,.8,1.25))
    piece(list,evaluated,"plate_flat",0,Vector3(0,.01,.078),Vector3(1.5,.5,1))
    piece(list,evaluated,"joint",2,Vector3(0,-.055,0),Vector3(.52,.55,.52))
    piece(list,evaluated,"plate_flat",2,Vector3(0,.080,.074),Vector3(.96,.57,1.3),Vector3.ZERO,3.5)
    piece(list,evaluated,"plate_shell",2,Vector3(0,.08,-.045),Vector3(1.0,.63,1.6),Vector3(0,PI,0))
    for side in range(2):
        var sign: float=-1 if side==0 else 1;var upper: int=3 if side==0 else 6;var lower: int=upper+1;var hand: int=upper+2
        for bone in [upper,lower]:
            piece(list,evaluated,"joint",bone,Vector3.ZERO,Vector3(.76,.74,.76),Vector3(0,0,PI/2))
            piece(list,evaluated,"plate_flat",bone,Vector3(0,-.145,.058),Vector3(.62,.72,.90))
            piece(list,evaluated,"plate_shell",bone,Vector3(0,-.145,-.044),Vector3(.64,.75,1),Vector3(0,PI,0))
        piece(list,evaluated,"plate_shell",upper,Vector3(sign*.02,.01,0),Vector3(.88,.54,1.5),Vector3(0,0,sign*PI/2))
        link(list,"shaft",origins[upper],origins[lower],.72,upper);link(list,"shaft",origins[lower],origins[hand],.58,lower)
        # A telescoping piston spans two anchors across the elbow.
        var a: Vector3=anchored(evaluated,upper,Vector3(sign*.045,-.10,-.040));var b: Vector3=anchored(evaluated,lower,Vector3(sign*.045,-.14,-.040));var direction: Vector3=(b-a).normalized();var length: float=a.distance_to(b)
        link(list,"shaft",a,a+direction*length*.67,1.15,upper);link(list,"shaft",a+direction*length*.42,b,.45,lower)
        piece(list,evaluated,"joint",hand,Vector3(0,-.015,0),Vector3(.34,.42,.34),Vector3(0,0,PI/2))
        piece(list,evaluated,"plate_bracket",hand,Vector3(0,-.055,.025),Vector3(.60,.55,.60))
        for finger in range(3):
            # Two anterior fingers oppose a posterior thumb; all reuse the shaft.
            var thumb: bool=finger==2;var local:=Vector3(0,-.103,-.031) if thumb else Vector3((finger*2-1)*.027,-.105,.047)
            var base: Vector3=anchored(evaluated,hand,local);var hand_basis: Basis=frame(evaluated,hand).basis
            var angle: float=-.05-state["grip"]*.26 if thumb else state["grip"]*.32
            var q:=Basis(Vector3.RIGHT,angle);var mid: Vector3=base+hand_basis*q*Vector3(0,-.052,0)
            var tip: Vector3=mid+hand_basis*q*q*Vector3(0,-.043,0)
            link(list,"shaft",base,mid,.37,hand);link(list,"shaft",mid,tip,.32,hand)
        var thigh: int=9 if side==0 else 12;var shin: int=thigh+1;var foot: int=thigh+2
        for bone in [thigh,shin]:
            piece(list,evaluated,"joint",bone,Vector3.ZERO,Vector3(.85,.84,.85),Vector3(0,0,PI/2))
            piece(list,evaluated,"plate_flat",bone,Vector3(0,-.185,.070),Vector3(.80,.91,1.1))
            piece(list,evaluated,"plate_shell",bone,Vector3(0,-.185,-.065),Vector3(.81,1.0,1.45),Vector3(0,PI,0))
        link(list,"shaft",origins[thigh],origins[shin],1.05,thigh);link(list,"shaft",origins[shin],origins[foot],.94,shin)
        piece(list,evaluated,"plate_bracket",shin,Vector3(0,.015,.068),Vector3(1,1,.85))
        piece(list,evaluated,"joint",foot,Vector3.ZERO,Vector3(.58,.65,.58),Vector3(0,0,PI/2))
        piece(list,evaluated,"plate_flat",foot,Vector3(0,-.0842,.075),Vector3(.92,.97,1.3),Vector3(-PI/2,0,0))
    var frames:=PackedFloat32Array();var paths: Array=[]
    if state["cables"]:
        var specs: Array=[]
        for side in range(2):
            var sign: float=-1 if side==0 else 1;var upper: int=3 if side==0 else 6;var thigh: int=9 if side==0 else 12
            specs.append([upper,Vector3(sign*.06,-.13,-.060),upper+1,Vector3(sign*.055,-.16,-.06),Vector3(sign*.18,0,-1),.42])
            specs.append([thigh,Vector3(sign*.06,-.22,-.075),thigh+1,Vector3(sign*.055,-.17,-.065),Vector3(sign*.20,0,-1),.43])
            specs.append([0,Vector3(sign*.13,.06,-.07),1,Vector3(sign*.15,.28,-.10),Vector3(sign*.3,0,-1),.60])
        for spec in specs:
            var a: Vector3=anchored(evaluated,spec[0],spec[1]);var b: Vector3=anchored(evaluated,spec[2],spec[3]);var bow: Vector3=Basis(evaluated["rotations"][spec[0]])*spec[4]
            var path: Dictionary=cable_path(a,b,bow,spec[5]);var index: int=paths.size();paths.append(path);frames.append_array(path["packet"])
            list.append({"master":"cable","pose":Transform3D.IDENTITY,"bone":int(spec[0]),"curve":index,"radius_scale":1.0,"emission":0.0})
    if state["focus"]=="arm":list=list.filter(func(p: Dictionary):return p["bone"] in [3,4,5])
    elif state["focus"]=="hand":list=list.filter(func(p: Dictionary):return p["bone"]==5)
    elif state["focus"]=="head":list=list.filter(func(p: Dictionary):return p["bone"]==2)
    if state["focus"]=="master":
        list=[];frames.clear();paths=[]
        if state["master"]=="cable":
            var path: Dictionary=cable_path(Vector3(0,-.22,0),Vector3(0,.22,0),Vector3(1,0,.1),.50);paths.append(path);frames.append_array(path["packet"])
            list.append({"master":"cable","pose":Transform3D.IDENTITY,"bone":-1,"curve":0,"radius_scale":1.0,"emission":0.0})
        else:add(list,state["master"],Transform3D.IDENTITY,-1,1.0)
    elif state["floor"] and state["focus"]=="body":add(list,"ground",Transform3D.IDENTITY)
    return {"parts":list,"curves":frames,"paths":paths,"rig":evaluated,"pose":pose}
