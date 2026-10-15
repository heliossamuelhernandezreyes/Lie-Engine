extends RefCounted
## Shared immutable 96-byte instance / 16-byte job packet preparation.
## An adapter opts in with an explicit identity for its immutable assembly.
var _identity:=PackedByteArray()
var _levels: Dictionary={}
var _budget:=Vector2i(-1,-1)
var builds: int=0
var reuses: int=0
func packet(identity: PackedByteArray, source: Callable, catalog: Dictionary, selected: int, max_work: int, max_instances: int) -> Dictionary:
    var budget:=Vector2i(max_work,max_instances)
    if budget!=_budget:_levels.clear();_budget=budget
    if not identity.is_empty() and identity==_identity and _levels.has(selected):
        reuses+=1;return _levels[selected].duplicate()
    if identity!=_identity or identity.is_empty():_identity=identity.duplicate();_levels.clear()
    var entries: Array=source.call();var result: Dictionary={}
    for level in range(selected,3):
        var data:=PackedFloat32Array();var jobs:=PackedInt32Array();var work: int=0
        for entry in entries:
            var pose: Transform3D=entry["pose"];var master: Dictionary=catalog["masters"][entry["master"]];var span: Dictionary=master["levels"][level];var index: int=data.size()/24
            for v in [pose.basis.x,pose.basis.y,pose.basis.z,pose.origin]:data.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
            var tint: Array=entry.get("tint",[1.,1.,1.,0.])
            data.append_array(PackedFloat32Array([index*128,0,0,0,float(tint[0]),float(tint[1]),float(tint[2]),float(tint[3])]))
            jobs.append_array(PackedInt32Array([span["start"],span["count"],index,work]));work+=int(span["count"])
        result={"instances":data.to_byte_array(),"jobs":jobs.to_byte_array(),"count":entries.size(),"work":work,"lod":level,"ok":work>0 and work<=max_work and entries.size()<=max_instances}
        if work<=max_work:break
    builds+=1
    if not identity.is_empty():_levels[selected]=result.duplicate()
    return result
func metrics() -> Dictionary:return {"builds":builds,"reuses":reuses,"cached_lods":_levels.size(),"scope":"adapter-declared immutable assembly identity; camera and lights excluded"}
