extends RefCounted
## Fixed 2x2 Gaussian quadrature of a uniform, one-sided Lambert rectangle.
## Logical identity and total power survive expansion; no native light copy.
const Model=preload("res://lie11_model.gd")
static func valid_shape(shape: Dictionary) -> bool:
    if shape.size()!=5 or not shape.has_all(["size","u","v","n","type"]) or shape["type"]!="rectangle":return false
    if not shape["size"] is Vector2 or not shape["size"].is_finite() or shape["size"].x<.0001 or shape["size"].y<.0001 or shape["size"].x>1000. or shape["size"].y>1000.:return false
    for key in ["u","v","n"]:
        if not shape[key] is Vector3 or not shape[key].is_finite() or absf(shape[key].length_squared()-1.)>.0001:return false
    return absf(shape["u"].dot(shape["v"]))<.0001 and absf(shape["u"].dot(shape["n"]))<.0001 and absf(shape["v"].dot(shape["n"]))<.0001
static func compile(snapshot: Dictionary,shapes: Dictionary) -> Dictionary:
    if not Model.valid_light_codes(snapshot.get("lights",[])) or not snapshot.get("ids") is Array:return {}
    var ids: Array=snapshot["ids"];var source: Array=snapshot["lights"]
    if ids.size()>source.size():return {}
    var lights: Array=[];var channels: Array=[];var parents: Array=[];var descriptors:=PackedByteArray();descriptors.resize(128)
    for i in range(ids.size()):
        var id: String=ids[i]
        if id=="":continue
        var code: Dictionary=source[i]
        if not shapes.has(id):lights.append(code.duplicate(true));channels.append(id);parents.append(id);continue
        var shape: Dictionary=shapes[id]
        if not valid_shape(shape):return {}
        var size: Vector2=shape["size"];var u: Vector3=shape["u"];var v: Vector3=shape["v"];var normal: Vector3=shape["n"]
        var pos: Array=code["position"];var center:=Vector3(pos[0],pos[1],pos[2]);var q: int=0
        for y in [-1.,1.]:
            for x in [-1.,1.]:
                if lights.size()>=8:return {}
                var p: Vector3=center+(u*(x*size.x)+v*(y*size.y))/sqrt(12.)
                var rgb: Array=code["power_rgb"]
                var at: int=lights.size()*16
                descriptors.encode_float(at,normal.x);descriptors.encode_float(at+4,normal.y);descriptors.encode_float(at+8,normal.z);descriptors.encode_float(at+12,1.)
                lights.append({"position":[p.x,p.y,p.z],"radius":code["radius"],"power_rgb":[rgb[0]*.25,rgb[1]*.25,rgb[2]*.25]})
                channels.append(id+"/q"+str(q));parents.append(id);q+=1
    if lights.size()>8:return {}
    if lights.is_empty():lights.append({"position":[0.,0.,0.],"radius":1.,"power_rgb":[0.,0.,0.]})
    return {"schema":"lie-area-codes/1","lights":lights,"ids":channels,"parent_ids":parents,"logical_ids":ids.duplicate(),"logical_lights":source.duplicate(true),"emission_descriptors":descriptors,"quadrature":"2x2 Gauss-Legendre; relative total RGB power"}
