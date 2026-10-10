extends RefCounted
## OBB diagnostics for rigid assemblies. Contact is allowed; penetration is not.
## Connected neighbors may intentionally overlap at mechanical joints.
const Doc=preload("res://workshop/lie_document.gd")

static func overlap(a: Transform3D,b: Transform3D,tolerance: float=.002) -> bool:
    var aa: Array[Vector3]=[a.basis.x.normalized(),a.basis.y.normalized(),a.basis.z.normalized()]
    var bb: Array[Vector3]=[b.basis.x.normalized(),b.basis.y.normalized(),b.basis.z.normalized()]
    var ea: Vector3=a.basis.get_scale()*.5
    var eb: Vector3=b.basis.get_scale()*.5
    var delta: Vector3=b.origin-a.origin
    var axes: Array[Vector3]=aa.duplicate(); axes.append_array(bb)
    for x in aa:
        for y in bb:
            var axis: Vector3=x.cross(y)
            if axis.length_squared()>1e-10: axes.append(axis.normalized())
    for axis in axes:
        var radius: float=0
        for k in range(3): radius+=absf(axis.dot(aa[k]))*ea[k]+absf(axis.dot(bb[k]))*eb[k]
        if absf(delta.dot(axis))>=radius-tolerance: return false
    return true

static func diagnostics(candidate: Dictionary,evaluated: Dictionary) -> Array:
    var warnings: Array=[]
    var parts: Array=candidate["pieces"]
    for i in range(parts.size()):
        var a: Dictionary=parts[i]; var pose: Transform3D=evaluated["poses"][a["id"]]
        var extent: float=(absf(pose.basis.x.y)+absf(pose.basis.y.y)+absf(pose.basis.z.y))*.5
        if pose.origin.y-extent< -1.052: warnings.append({"kind":"floor","a":a["id"]})
        for j in range(i+1,parts.size()):
            var b: Dictionary=parts[j]
            if a["parent"]==b["id"] or b["parent"]==a["id"]: continue
            if overlap(pose,evaluated["poses"][b["id"]]): warnings.append({"kind":"overlap","a":a["id"],"b":b["id"]})
    return warnings

static func segment_hit(a: Vector3,b: Vector3,pose: Transform3D) -> bool:
    var inv: Transform3D=pose.affine_inverse()
    var p: Vector3=inv*a; var delta: Vector3=inv*b-p
    var lo: float=0; var hi: float=1
    for axis in range(3):
        if absf(delta[axis])<1e-10:
            if absf(p[axis])>.5: return false
        else:
            var u: float=(-.5-p[axis])/delta[axis]; var v: float=(.5-p[axis])/delta[axis]
            lo=maxf(lo,minf(u,v)); hi=minf(hi,maxf(u,v))
    return lo<=hi

static func rain_position(index: int,time_value: float) -> Vector3:
    # Analytic ballistic fall. Fixed phase distribution is independent of FPS.
    var duration: float=sqrt(2*(2.8+1.05)/9.81)
    var t: float=fposmod(time_value+float(index)*duration/24,duration)
    return Vector3(-1.65+fposmod(float(index)*.6180339,1)*3.3,2.8-.5*9.81*t*t,-.8+fposmod(float(index)*.4142135,1)*2.0)

static func optical_sheets(candidate: Dictionary,time_value: float,eye: Transform3D,poses: Dictionary) -> Array:
    var setting: Dictionary=candidate["settings"]
    if setting["fluid"]=="water":
        return [{"center":[0,-1.02,.5],"right":[1,0,0],"up":[0,0,-1],"half_width":1.65,"half_height":1.1,"thickness":.08,"sigma":[.35,.07,.035],"ior":1.333,"kind":1,"wave":setting["wave_amplitude"],"frequency":8,"gray":1}]
    var out: Array=[]
    if setting["fluid"]!="rain": return out
    for i in range(int(setting["rain_count"])):
        var position: Vector3=rain_position(i,time_value)
        var collided: bool=false
        # A falling drop is hidden after the first solid impact in its current
        # cycle. Test its entire fall segment to avoid frame-dependent tunneling.
        var start:=Vector3(position.x,2.8,position.z)
        for pose in poses.values():
            if segment_hit(start,position,pose): collided=true; break
        if collided: continue
        out.append({"center":Doc.arr(position),"right":Doc.arr(eye.basis.x.normalized()),"up":Doc.arr(eye.basis.y.normalized()),"half_width":.022,"half_height":.055,"thickness":.025,"sigma":[.04,.015,.005],"ior":1.333,"kind":2,"wave":0,"frequency":0,"gray":1})
    return out
