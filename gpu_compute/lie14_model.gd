extends RefCounted
## Rigid local->world master instances. Perception boxes never define shading.
const Model=preload("res://lie11_model.gd")
const MAX_INSTANCES: int=8
const BASE_ANGLES: Array=[-.35,1.1,-.85]
const MOVED_ANGLES: Array=[-.95,1.7,-.55]

static func values(v: Vector3) -> Array:
    return [v.x,v.y,v.z]

static func skeleton(angles: Array) -> Array[Transform3D]:
    var output: Array[Transform3D]=[]
    if angles.size()!=3: return output
    for angle in angles:
        if not is_finite(float(angle)) or absf(float(angle))>2.1: return output
    var basis:=Basis.IDENTITY
    var pivot:=Vector3(-.65,-1,0)
    for i in range(3):
        basis=basis*Basis(Vector3.BACK,float(angles[i]))
        if i==2: basis=basis*Basis(Vector3.RIGHT,.3)
        output.append(Transform3D(basis,pivot+basis*Vector3(0,.6,0)))
        pivot+=basis*Vector3(0,1.2,0)
    return output

static func blocked(a: Vector3,b: Vector3,poses: Array[Transform3D]) -> bool:
    for pose in poses:
        var p: Vector3=pose.affine_inverse()*a
        var q: Vector3=pose.affine_inverse()*b
        var d: Vector3=q-p
        var lo: float=.001
        var hi: float=.999
        if absf(d.y)<1e-10:
            if absf(p.y)>.6: continue
        else:
            var u: float=(-.6-p.y)/d.y
            var v: float=(.6-p.y)/d.y
            lo=maxf(lo,minf(u,v))
            hi=minf(hi,maxf(u,v))
        var aa: float=d.x*d.x+d.z*d.z
        var bb: float=2*(p.x*d.x+p.z*d.z)
        var cc: float=p.x*p.x+p.z*p.z-.18*.18
        if aa<1e-12:
            if cc>0: continue
        else:
            var disc: float=bb*bb-4*aa*cc
            if disc<0: continue
            var root: float=sqrt(disc)
            lo=maxf(lo,(-bb-root)/(2*aa))
            hi=minf(hi,(-bb+root)/(2*aa))
        if lo<=hi: return true
    return false

static func scene_model(master: Dictionary,name: String,angles: Array=[]) -> Dictionary:
    var chosen: Array=angles if not angles.is_empty() else (MOVED_ANGLES if name=="pose" else BASE_ANGLES)
    var poses: Array[Transform3D]=skeleton(chosen)
    if poses.size()!=3: return {}
    var patches: Array=[]
    for i in range(poses.size()):
        for original in master["patches"]:
            var patch: Dictionary=original.duplicate(true)
            patch["position"]=values(poses[i]*Model.vector(original["position"]))
            patch["normal"]=values(poses[i].basis*Model.vector(original["normal"]))
            patch["material"]="red" if i==1 else "metal"
            patches.append(patch)
    for wall in [false,true]:
        for row in range(4):
            for col in range(4):
                var p:=Vector3(-2+float(col)+.5,-1.05,-2+float(row)+.5)
                if wall: p=Vector3(-2+float(col)+.5,-1+float(row)+.5,-2)
                patches.append({"position":values(p),"normal":[0,0,1] if wall else [0,1,0],
                    "area":1.0,"gray_mean":.7,"material":"room"})
    var visibility: Array=[]
    var n: int=patches.size()
    visibility.resize(n*n)
    visibility.fill(0)
    for i in range(n):
        for j in range(i+1,n):
            var a: Vector3=Model.vector(patches[i]["position"])+Model.vector(patches[i]["normal"])*.003
            var b: Vector3=Model.vector(patches[j]["position"])+Model.vector(patches[j]["normal"])*.003
            var valid: int=0 if blocked(a,b,poses) else 1
            visibility[i*n+j]=valid
            visibility[j*n+i]=valid
    return {"schema":1,"patches":patches,"factor_normalization":"symmetric_local",
        "materials":{"metal":{"absorption_code":220,"tint_linear":[.55,.8,1]},
            "red":{"absorption_code":900 if name=="absorbing" else 180,"tint_linear":[1,.12,.08]},
            "room":{"absorption_code":300,"tint_linear":[1,1,1]}},
        "lights":[{"position":[1.4,2.2,1.8] if name=="light" else [-1.6,2.1,1.5],
            "power_rgb":[0,0,0] if name=="dark" else [60,50,40],"radius":7}],
        "bounces":0 if name=="direct" else 2,"blockers":[],"mesh_visibility":visibility,
        "secondary_radii":{"radius_max":4,"radius_decay":.82,"power_reference":.03}}

static func instance_bytes(poses: Array[Transform3D],model: Dictionary) -> PackedByteArray:
    var data:=PackedFloat32Array()
    data.resize(MAX_INSTANCES*24)
    for i in range(5):
        var pose: Transform3D=poses[i] if i<poses.size() else Transform3D.IDENTITY
        var material: Dictionary=model["materials"]["red" if i==1 else "metal" if i<3 else "room"]
        var tint: Vector3=Model.vector(material["tint_linear"])
        var offset: int=i*18 if i<3 else 54+(i-3)*16
        var row:=PackedFloat32Array()
        for v in [pose.basis.x,pose.basis.y,pose.basis.z,pose.origin]:
            row.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
        row.append_array(PackedFloat32Array([.18,.6,1.0 if i<3 else 0.0,float(offset),
            tint.x,tint.y,tint.z,float(material["absorption_code"])/1000.0]))
        for k in range(24): data[i*24+k]=row[k]
    return data.to_byte_array()

static func box_visible(pose: Transform3D,eye: Transform3D,tan_y: float,aspect: float) -> bool:
    # Six half-space rejection against transformed box corners, conservative
    # when a box crosses the near plane. Faces are bounds, never draw surfaces.
    var corners: Array[Vector3]=[]
    var inverse_eye: Transform3D=eye.affine_inverse()
    for x in [-.18,.18]:
        for y in [-.6,.6]:
            for z in [-.18,.18]: corners.append(inverse_eye*(pose*Vector3(x,y,z)))
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
            if value>=0:
                outside=false
                break
        if outside: return false
    return true
