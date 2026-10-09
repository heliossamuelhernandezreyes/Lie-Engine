extends RefCounted
## Static spatial contract and reciprocal transfer cache. Runtime transport is GPU.

static func vector(value: Array) -> Vector3:
    return Vector3(float(value[0]),float(value[1]),float(value[2]))

static func load_room() -> Dictionary:
    var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/lie11-room.json"))
    if not parsed is Dictionary:
        push_error("LIE-11 requires generated fixtures/lie11-room.json; run tools/lie_light_transport.py")
        return {}
    return parsed

static func scenario(base: Dictionary, name: String) -> Dictionary:
    var model: Dictionary=base.duplicate(true)
    model["bounces"]=2
    match name:
        "direct": model["bounces"]=0
        "absorbing": model["materials"]["red"]["absorption_code"]=980
        "blocked": model["blockers"]=[[[-0.62,-0.02,-1.02],[-0.58,1.52,1.02]]]
        "moved": model["lights"][0]["position"]=[0.65,0.6,0.5]
        "cool": model["lights"][0]["power_rgb"]=[8.0,20.0,40.0]
        "bounce": pass
        _: push_error("Unknown LIE-11 scenario: "+name)
    return model

static func blocked(a: Vector3, b: Vector3, boxes: Array) -> bool:
    var delta: Vector3=b-a
    for bounds in boxes:
        var low: Vector3=vector(bounds[0])
        var high: Vector3=vector(bounds[1])
        var near_t: float=0.001
        var far_t: float=0.999
        for axis in range(3):
            if absf(delta[axis])<0.00000001:
                if a[axis]<low[axis] or a[axis]>high[axis]:
                    near_t=1.0
                    far_t=0.0
                    break
            else:
                var u: float=(low[axis]-a[axis])/delta[axis]
                var v: float=(high[axis]-a[axis])/delta[axis]
                near_t=maxf(near_t,minf(u,v))
                far_t=minf(far_t,maxf(u,v))
        if near_t<=far_t:
            return true
    return false

static func factor_bytes(model: Dictionary) -> PackedByteArray:
    var patches: Array=model["patches"]
    var n: int=patches.size()
    var factors:=PackedFloat32Array()
    factors.resize(n*n)
    var largest_row: float=1.0
    for i in range(n):
        for j in range(i+1,n):
            var a: Dictionary=patches[i]
            var b: Dictionary=patches[j]
            var pa: Vector3=vector(a["position"])
            var pb: Vector3=vector(b["position"])
            var d: Vector3=pb-pa
            var d2: float=d.length_squared()
            var visibility: Array=model.get("mesh_visibility",[])
            if not visibility.is_empty() and int(visibility[i*n+j])==0:
                continue
            if d2<0.0000000001 or blocked(pa,pb,model.get("blockers",[])):
                continue
            var direction: Vector3=d.normalized()
            var ca: float=maxf(vector(a["normal"]).dot(direction),0.0)
            var cb: float=maxf(-vector(b["normal"]).dot(direction),0.0)
            var coupling: float=float(a["area"])*float(b["area"])*ca*cb/(PI*d2)
            factors[i*n+j]=coupling/float(a["area"])
            factors[j*n+i]=coupling/float(b["area"])
    for i in range(n):
        var row: float=0.0
        for j in range(n):
            row+=factors[i*n+j]
        largest_row=maxf(largest_row,row)
    for i in range(factors.size()):
        factors[i]/=largest_row
    return factors.to_byte_array()

static func patch_bytes(model: Dictionary) -> PackedByteArray:
    var output:=PackedFloat32Array()
    for p in model["patches"]:
        var position: Vector3=vector(p["position"])
        var normal: Vector3=vector(p["normal"])
        var material: Dictionary=model["materials"][p["material"]]
        var tint: Vector3=vector(material["tint_linear"])
        output.append_array(PackedFloat32Array([
            position.x,position.y,position.z,float(p["area"]),
            normal.x,normal.y,normal.z,float(p["gray_mean"]),
            tint.x,tint.y,tint.z,float(material["absorption_code"])/1000.0]))
    return output.to_byte_array()

static func light_bytes(model: Dictionary) -> PackedByteArray:
    var output:=PackedFloat32Array()
    output.resize(16*8)
    var index: int=0
    for light in model["lights"]:
        var position: Vector3=vector(light["position"])
        var power: Vector3=vector(light["power_rgb"])
        var values:=PackedFloat32Array([position.x,position.y,position.z,float(light["radius"]),power.x,power.y,power.z,0.0])
        for k in range(8):
            output[index*8+k]=values[k]
        index+=1
    return output.to_byte_array()

static func blocker_bytes(model: Dictionary) -> PackedByteArray:
    var output:=PackedFloat32Array()
    output.resize(16*8)
    var index: int=0
    for bounds in model.get("blockers",[]):
        var low: Vector3=vector(bounds[0])
        var high: Vector3=vector(bounds[1])
        var values:=PackedFloat32Array([low.x,low.y,low.z,0.0,high.x,high.y,high.z,0.0])
        for k in range(8):
            output[index*8+k]=values[k]
        index+=1
    return output.to_byte_array()

static func triangle_bytes(model: Dictionary) -> PackedByteArray:
    var output:=PackedFloat32Array()
    for triangle in model.get("triangles",[]):
        for point in triangle:
            var v: Vector3=vector(point)
            output.append_array(PackedFloat32Array([v.x,v.y,v.z,0.0]))
    if output.is_empty(): output.resize(12)
    return output.to_byte_array()

static func valid(model: Dictionary) -> bool:
    if int(model.get("schema",0))!=1:
        return false
    var patches: Array=model.get("patches",[])
    var lights: Array=model.get("lights",[])
    var boxes: Array=model.get("blockers",[])
    var triangles: Array=model.get("triangles",[])
    if triangles.size()>16384: return false
    for triangle in triangles:
        if not triangle is Array or triangle.size()!=3: return false
        for point in triangle:
            if not point is Array or point.size()!=3 or not vector(point).is_finite(): return false
    var visibility: Array=model.get("mesh_visibility",[])
    if not visibility.is_empty():
        var n: int=patches.size()
        if visibility.size()!=n*n: return false
        for i in range(n):
            for j in range(n):
                if float(visibility[i*n+j])!=0.0 and float(visibility[i*n+j])!=1.0: return false
                if visibility[i*n+j]!=visibility[j*n+i]: return false
    if patches.is_empty() or patches.size()>1024 or lights.is_empty() or lights.size()>16 or boxes.size()>16:
        return false
    for p in patches:
        if not p is Dictionary or (p.get("position",[]) as Array).size()!=3 or (p.get("normal",[]) as Array).size()!=3:
            return false
        var position: Vector3=vector(p["position"])
        var normal: Vector3=vector(p["normal"])
        if not position.is_finite() or not normal.is_finite() or absf(normal.length_squared()-1.0)>0.00001:
            return false
        if not is_finite(float(p.get("area",0))) or float(p["area"])<=0.0 or not is_finite(float(p.get("gray_mean",-1))) or float(p.get("gray_mean",-1))<0.0 or float(p["gray_mean"])>1.0:
            return false
        var material: Dictionary=model["materials"].get(p.get("material",""),{})
        if material.is_empty():
            return false
        var absorption: float=float(material.get("absorption_code",-1))
        var tint: Vector3=vector(material.get("tint_linear",[-1,-1,-1]))
        if not is_finite(absorption) or absorption!=floorf(absorption) or absorption<0.0 or absorption>1000.0 or not tint.is_finite():
            return false
        if minf(tint.x,minf(tint.y,tint.z))<0.0 or maxf(tint.x,maxf(tint.y,tint.z))>1.0:
            return false
    for light in lights:
        if (light.get("position",[]) as Array).size()!=3 or (light.get("power_rgb",[]) as Array).size()!=3:
            return false
        var position: Vector3=vector(light["position"])
        var power: Vector3=vector(light["power_rgb"])
        var radius: float=float(light.get("radius",0))
        if not position.is_finite() or not power.is_finite() or minf(power.x,minf(power.y,power.z))<0 or not is_finite(radius) or radius<=0:
            return false
    for bounds in boxes:
        if (bounds as Array).size()!=2 or (bounds[0] as Array).size()!=3 or (bounds[1] as Array).size()!=3:
            return false
        var low: Vector3=vector(bounds[0])
        var high: Vector3=vector(bounds[1])
        if not low.is_finite() or not high.is_finite() or low.x>=high.x or low.y>=high.y or low.z>=high.z:
            return false
    return int(model.get("bounces",2))>=0 and int(model.get("bounces",2))<=8
