extends RefCounted
## Versioned transport policy; all areas in square meters, linear RGB power.
const DEFAULTS={"angular_sectors":6,"area_budget":true,"reference_area":1.0,"roughness_split":.5,"dynamic_occluders":[],"visibility_revision":0}
static func integer_value(value: Variant,low: int,high: int) -> bool:
    return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and value>=low and value<=high
static func valid(options: Variant) -> bool:
    if not options is Dictionary:return false
    for key in options:
        if not DEFAULTS.has(key):return false
    var q: Dictionary=DEFAULTS.duplicate(true);q.merge(options,true)
    if not integer_value(q.angular_sectors,1,6) or int(q.angular_sectors) not in [1,6] or not q.area_budget is bool:return false
    for key in ["reference_area","roughness_split"]:
        if not (q[key] is int or q[key] is float) or not is_finite(float(q[key])):return false
    if q.reference_area<1.17549435e-38 or q.reference_area>3.402823466e38 or q.roughness_split<0.0 or q.roughness_split>1.0:return false
    if not integer_value(q.visibility_revision,0,0xffffffff):return false
    if not q.dynamic_occluders is Array or q.dynamic_occluders.size()>16:return false
    for box in q.dynamic_occluders:
        if not box is Array or box.size()!=2:return false
        for p in box:
            if not p is Array or p.size()!=3:return false
            for v in p:
                if not (v is int or v is float) or not is_finite(float(v)):return false
        for k in range(3):
            if box[0][k]>=box[1][k]:return false
    return true

static func packet(areas: Array,options: Dictionary) -> PackedByteArray:
    if not valid(options) or areas.is_empty() or areas.size()>1024:return PackedByteArray()
    var q: Dictionary=DEFAULTS.duplicate(true);q.merge(options,true)
    var bytes:=PackedInt32Array([q.angular_sectors,1 if q.area_budget else 0,q.dynamic_occluders.size(),q.visibility_revision]).to_byte_array()
    bytes.append_array(PackedFloat32Array([q.reference_area,q.roughness_split,0,0]).to_byte_array())
    if not is_finite(bytes.decode_float(16)) or bytes.decode_float(16)<=0:return PackedByteArray()
    bytes.resize(32+(areas.size()+32)*16)
    for i in range(areas.size()):
        if not (areas[i] is int or areas[i] is float) or not is_finite(float(areas[i])) or areas[i]<=0:return PackedByteArray()
        bytes.encode_float(32+i*16,float(areas[i])/float(q.reference_area))
        if not is_finite(bytes.decode_float(32+i*16)) or bytes.decode_float(32+i*16)<=0:return PackedByteArray()
    for j in range(q.dynamic_occluders.size()):
        for side in range(2):
            for k in range(3):
                var at: int=32+(areas.size()+j*2+side)*16+k*4
                bytes.encode_float(at,q.dynamic_occluders[j][side][k])
                if not is_finite(bytes.decode_float(at)):return PackedByteArray()
        for k in range(3):
            if bytes.decode_float(32+(areas.size()+j*2)*16+k*4)>=bytes.decode_float(32+(areas.size()+j*2+1)*16+k*4):return PackedByteArray()
    return bytes
