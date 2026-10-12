extends RefCounted
## Thin-sheet code shared by transport and camera-only optical sprites.
static func v(a: Array) -> Vector3:
    return Vector3(float(a[0]),float(a[1]),float(a[2]))

static func valid(sheets: Array, limit: int=16) -> bool:
    if sheets.size()>limit: return false
    for s in sheets:
        if not s is Dictionary: return false
        for key in ["center","right","up","sigma"]:
            if not s.get(key) is Array or (s[key] as Array).size()!=3 or not v(s[key]).is_finite(): return false
        var r: Vector3=v(s["right"])
        var u: Vector3=v(s["up"])
        if absf(r.length_squared()-1)>.00001 or absf(u.length_squared()-1)>.00001 or absf(r.dot(u))>.00001: return false
        for key in ["half_width","half_height","ior"]:
            if not is_finite(float(s.get(key,0))) or float(s.get(key,0))<=0: return false
        if not is_finite(float(s.get("thickness",-1))) or float(s.get("thickness",-1))<0: return false
        var sigma: Vector3=v(s["sigma"])
        if minf(sigma.x,minf(sigma.y,sigma.z))<0: return false
        if int(s.get("kind",0))<0 or int(s.get("kind",0))>2: return false
        for key in ["wave","frequency"]:
            if not is_finite(float(s.get(key,0))) or float(s.get(key,0))<0: return false
    return true

static func bytes(sheets: Array, visual: bool=false) -> PackedByteArray:
    var data:=PackedFloat32Array()
    for s in sheets:
        for pair in [["center","thickness"],["right","half_width"],["up","half_height"],["sigma","ior"]]:
            var vec: Vector3=v(s[pair[0]])
            data.append_array(PackedFloat32Array([vec.x,vec.y,vec.z,float(s[pair[1]])]))
        if visual: data.append_array(PackedFloat32Array([float(s.get("kind",0)),float(s.get("wave",0)),float(s.get("frequency",8)),float(s.get("gray",1))]))
    data.resize((64*20) if visual else (16*16))
    return data.to_byte_array()
