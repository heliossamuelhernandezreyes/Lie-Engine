extends RefCounted
## Fixed, stable GPU slots; unused slots have zero reflectance and no blocker.
const Doc=preload("res://workshop/lie_document.gd")
const Legacy=preload("res://lie15_model.gd")
const SLOTS: int=30

static func build(candidate: Dictionary,evaluated: Dictionary,masters: Dictionary) -> Dictionary:
    var poses: Array[Transform3D]=[]; var types: Array=[]; var properties: Array=[]
    for i in range(SLOTS):
        poses.append(Transform3D(Basis.IDENTITY.scaled_local(Vector3(.02,.02,.02)),Vector3(1000,1000,1000)))
        types.append(""); properties.append({})
    for p in candidate["pieces"]:
        var slot: int=int(p["slot"])
        poses[slot]=evaluated["poses"][p["id"]]; types[slot]=p["master"]; properties[slot]=p
    var mats: Dictionary=candidate["materials"].duplicate(true)
    mats["unused"]={"tint_linear":[0,0,0],"absorption_code":1000,"roughness":1,"metallic":0,"emission":0}
    var patches: Array=[]
    for i in range(SLOTS):
        var active: bool=not properties[i].is_empty()
        var master: Dictionary=masters[types[i] if active else "box"]
        for original in master["patches"]:
            var p: Dictionary=original.duplicate(true)
            var n: Vector3=Doc.vec(p["normal"])
            var scale: Vector3=poses[i].basis.get_scale()
            var axis: int=0 if absf(n.x)>.9 else 1 if absf(n.y)>.9 else 2
            p["position"]=Doc.arr(poses[i]*Doc.vec(p["position"]))
            p["normal"]=Doc.arr((poses[i].basis.inverse().transposed()*n).normalized())
            p["area"]=maxf(float(p["area"])*scale[(axis+1)%3]*scale[(axis+2)%3],.000001)
            p["material"]=properties[i]["material"] if active else "unused"
            patches.append(p)
    for wall in [false,true]:
        for row in range(4):
            for col in range(4): patches.append({"position":[-1.5+col,-.5+row,-2] if wall else [-1.5+col,-1.05,-1.5+row],"normal":[0,0,1] if wall else [0,1,0],"area":1,"gray_mean":.7,"material":"room"})
    var transport_mats: Dictionary=mats.duplicate(true)
    for name in transport_mats:
        transport_mats[name]["tint_linear"]=Doc.arr(Doc.vec(mats[name]["tint_linear"])*(1-float(mats[name]["metallic"])))
    var model: Dictionary={"schema":1,"patches":patches,"materials":transport_mats,"surface_materials":mats,"factor_normalization":"symmetric_local",
        "lights":candidate["lights"].duplicate(true),"bounces":candidate["settings"]["bounces"],"blockers":[],"optical_sheets":[],
        "secondary_radii":{"radius_max":4,"radius_decay":.82,"power_reference":.03}}
    if candidate["settings"]["fluid"]=="water":
        model["optical_sheets"]=[{"center":[0,-1.02,.5],"right":[1,0,0],"up":[0,0,-1],"half_width":1.65,"half_height":1.1,"thickness":.08,"sigma":[.35,.07,.035],"ior":1.333}]
    var floats:=PackedFloat32Array(); floats.resize(32*28)
    for i in range(32):
        var active: bool=i>=SLOTS or not properties[i].is_empty()
        var pose: Transform3D=poses[i] if i<SLOTS else Transform3D.IDENTITY
        var name: String="room" if i>=SLOTS else properties[i]["material"] if active else "unused"
        var m: Dictionary=mats[name]; var tint: Vector3=Doc.vec(m["tint_linear"])
        var offset: int=i*6 if i<SLOTS else SLOTS*6+(i-SLOTS)*16
        var row:=PackedFloat32Array()
        for v in [pose.basis.x,pose.basis.y,pose.basis.z,pose.origin]: row.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
        row.append_array(PackedFloat32Array([.5,.5,.5,float(offset),tint.x,tint.y,tint.z,float(m["absorption_code"])/1000,float(m["roughness"]),float(m["metallic"]),float(m["emission"]),1 if i<SLOTS and active else 0]))
        for k in range(28): floats[i*28+k]=row[k]
    model["instance_bytes"]=floats.to_byte_array(); model["poses"]=poses; model["slots"]=types
    model["signature"]=JSON.stringify([candidate["pieces"].map(func(p: Dictionary): return [p["id"],p["slot"],p["master"],p["material"]]),candidate["materials"],candidate["lights"],candidate["settings"]["bounces"],candidate["settings"]["fluid"]])
    return model
