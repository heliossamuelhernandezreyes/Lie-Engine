extends RefCounted
## Fifteen rigid pieces, one captured master. Scale normals by inverse transpose.
const Model=preload("res://lie11_model.gd")
const PARTS: int=15
const MAX_INSTANCES: int=32

static func values(v: Vector3) -> Array: return [v.x,v.y,v.z]
static func skeleton(phase: float=0,pose: bool=false) -> Array[Transform3D]:
    var out: Array[Transform3D]=[]
    if not is_finite(phase): return out
    out.append(Transform3D(Basis.IDENTITY.scaled_local(Vector3(.72,.82,.42)),Vector3(0,.55,0)))
    var head: Basis=Basis(Vector3.BACK,.08*sin(phase))*Basis(Vector3.UP,.25*sin(phase))
    out.append(Transform3D(head.scaled_local(Vector3(.58,.46,.46)),Vector3(0,1.25,0)))
    out.append(Transform3D(Basis.IDENTITY.scaled_local(Vector3(.55,.30,.36)),Vector3(0,-.025,0)))
    for side in [-1,1]:
        var pivot:=Vector3(float(side)*.50,.87,0)
        var a: float=-float(side)*(.10+(.65 if pose else .45*sin(phase)))
        var basis: Basis=Basis(Vector3.BACK,a)*Basis(Vector3.RIGHT,.15*sin(phase))
        out.append(Transform3D(basis.scaled_local(Vector3(.23,.55,.26)),pivot+basis*Vector3(0,-.275,0)))
        var elbow: Vector3=pivot+basis*Vector3(0,-.55,0)
        var lower: Basis=basis*Basis(Vector3.RIGHT,-(.65 if pose else .3+.25*cos(phase)))
        out.append(Transform3D(lower.scaled_local(Vector3(.22,.50,.25)),elbow+lower*Vector3(0,-.25,0)))
    for side in [-1,1]:
        var hip:=Vector3(float(side)*.18,-.17,0)
        var basis:=Basis(Vector3.RIGHT,float(side)*(.3 if pose else .22*sin(phase)))
        out.append(Transform3D(basis.scaled_local(Vector3(.25,.42,.28)),hip+basis*Vector3(0,-.21,0)))
        var knee: Vector3=hip+basis*Vector3(0,-.42,0)
        var lower: Basis=basis*Basis(Vector3.RIGHT,-(.35 if pose else .12*(1+sin(phase))))
        out.append(Transform3D(lower.scaled_local(Vector3(.23,.42,.25)),knee+lower*Vector3(0,-.21,0)))
        var ankle: Vector3=knee+lower*Vector3(0,-.42,0)
        out.append(Transform3D(lower.scaled_local(Vector3(.30,.16,.44)),ankle+lower*Vector3(0,-.01,.1)))
    for side in [-1,1]:
        out.append(Transform3D(head.scaled_local(Vector3(.10,.10,.065)),Vector3(0,1.25,0)+head*Vector3(float(side)*.14,.03,.245)))
    return out

static func material_name(i: int) -> String:
    if i==0: return "paint"
    if i in [2,9,12]: return "dark"
    if i>=13 and i<PARTS: return "eye"
    return "steel" if i<PARTS else "room"

static func materials(name: String) -> Dictionary:
    return {"steel":{"tint_linear":[.62,.78,.95],"absorption_code":150,"roughness":.34,"metallic":.85,"emission":0},
        "paint":{"tint_linear":[.9,.15,.07],"absorption_code":900 if name=="absorbing" else 200,"roughness":.5,"metallic":.12,"emission":0},
        "dark":{"tint_linear":[.12,.18,.23],"absorption_code":400,"roughness":.6,"metallic":.4,"emission":0},
        "eye":{"tint_linear":[.04,.8,1],"absorption_code":100,"roughness":.3,"metallic":0,"emission":.65},
        "room":{"tint_linear":[.7,.8,.9],"absorption_code":300,"roughness":.9,"metallic":0,"emission":0}}

static func blocked(a: Vector3,b: Vector3,poses: Array[Transform3D]) -> bool:
    for pose in poses:
        var inverse: Transform3D=pose.affine_inverse()
        var p: Vector3=inverse*a
        var q: Vector3=inverse*b
        if Model.blocked(p,q,[[[-.5,-.5,-.5],[.5,.5,.5]]]): return true
    return false

static func scene_model(master: Dictionary,name: String,phase: float=0) -> Dictionary:
    var poses: Array[Transform3D]=skeleton(phase,name=="pose")
    var mats: Dictionary=materials(name)
    var patches: Array=[]
    for i in range(PARTS):
        for original in master["patches"]:
            var p: Dictionary=original.duplicate(true)
            var n: Vector3=Model.vector(p["normal"])
            var scale: Vector3=poses[i].basis.get_scale()
            var axis: int=0 if absf(n.x)>.9 else 1 if absf(n.y)>.9 else 2
            p["position"]=values(poses[i]*Model.vector(p["position"]))
            p["normal"]=values((poses[i].basis.inverse().transposed()*n).normalized())
            p["area"]=scale[(axis+1)%3]*scale[(axis+2)%3]
            p["material"]=material_name(i)
            patches.append(p)
    for wall in [false,true]:
        for row in range(4):
            for col in range(4):
                patches.append({"position":[-2+float(col)+.5,-1+float(row)+.5,-2] if wall else [-2+float(col)+.5,-1.05,-2+float(row)+.5],"normal":[0,0,1] if wall else [0,1,0],"area":1,"gray_mean":.7,"material":"room"})
    var n: int=patches.size()
    var visibility: Array=[]
    visibility.resize(n*n)
    visibility.fill(0)
    for i in range(n):
        for j in range(i+1,n):
            # Reject non-facing node pairs before any expensive occlusion query.
            var a: Vector3=Model.vector(patches[i]["position"])
            var b: Vector3=Model.vector(patches[j]["position"])
            var na: Vector3=Model.vector(patches[i]["normal"])
            var nb: Vector3=Model.vector(patches[j]["normal"])
            if na.dot(b-a)<=0 or nb.dot(a-b)<=0: continue
            var v: int=0 if blocked(a+na*.003,b+nb*.003,poses) else 1
            visibility[i*n+j]=v
            visibility[j*n+i]=v
    var transport_mats: Dictionary=mats.duplicate(true)
    for key in transport_mats:
        var tint: Vector3=Model.vector(mats[key]["tint_linear"])*(1-float(mats[key]["metallic"]))
        transport_mats[key]["tint_linear"]=values(tint)
    return {"schema":1,"patches":patches,"factor_normalization":"symmetric_local","materials":transport_mats,"surface_materials":mats,
        "lights":[{"position":[1.6,2,1.5] if name=="light" else [-1.7,2.3,1.8],"power_rgb":[0,0,0] if name=="dark" else [130,115,95],"radius":7},
            {"position":[1.5,.8,-.5],"power_rgb":[0,0,0] if name=="dark" else [24,40,65],"radius":5}],"bounces":0 if name=="direct" else 2,"blockers":[],"mesh_visibility":visibility,
        "secondary_radii":{"radius_max":4,"radius_decay":.82,"power_reference":.03}}

static func instance_bytes(poses: Array[Transform3D],model: Dictionary) -> PackedByteArray:
    var data:=PackedFloat32Array()
    data.resize(MAX_INSTANCES*28)
    for i in range(PARTS+2):
        var pose: Transform3D=poses[i] if i<PARTS else Transform3D.IDENTITY
        var m: Dictionary=model["surface_materials"][material_name(i)]
        var tint: Vector3=Model.vector(m["tint_linear"])
        var offset: int=i*6 if i<PARTS else PARTS*6+(i-PARTS)*16
        var row:=PackedFloat32Array()
        for v in [pose.basis.x,pose.basis.y,pose.basis.z,pose.origin]: row.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
        row.append_array(PackedFloat32Array([.5,.5,.5,float(offset),tint.x,tint.y,tint.z,float(m["absorption_code"])/1000,float(m["roughness"]),float(m["metallic"]),float(m["emission"]),1 if i<PARTS else 0]))
        for k in range(28): data[i*28+k]=row[k]
    return data.to_byte_array()

static func box_visible(pose: Transform3D,eye: Transform3D,tan_y: float,aspect: float) -> bool:
    var corners: Array[Vector3]=[]
    var inv: Transform3D=eye.affine_inverse()
    for x in [-.5,.5]:
        for y in [-.5,.5]:
            for z in [-.5,.5]: corners.append(inv*(pose*Vector3(x,y,z)))
    for plane in range(6):
        var outside: bool=true
        for p in corners:
            var depth: float=-p.z
            var value: float=depth-.1
            match plane:
                1: value=100-depth
                2: value=depth*tan_y*aspect+p.x
                3: value=depth*tan_y*aspect-p.x
                4: value=depth*tan_y+p.y
                5: value=depth*tan_y-p.y
            if value>=0: outside=false; break
        if outside: return false
    return true
