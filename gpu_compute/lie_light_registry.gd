extends RefCounted
## Per-world stable emitter IDs. Immutable snapshots cross to the render thread.
## Units are meters and relative linear RGB power; no implicit lumen conversion.
const Model=preload("res://lie11_model.gd")
const CAPACITY: int=8
var revision: int=0
var _records: Dictionary={}
var _slots: Array[String]=[]

func upsert(id: String, code: Dictionary) -> bool:
    if id.is_empty() or id.length()>96 or not Model.valid_light_codes([code]):return false
    var clean: Dictionary={"position":code["position"].duplicate(),"power_rgb":code["power_rgb"].duplicate(),"radius":float(code["radius"])}
    if _records.get(id)==clean:return true
    if not _records.has(id):
        var slot: int=_slots.find("")
        if slot<0:
            if _slots.size()>=CAPACITY:return false
            _slots.append(id)
        else:_slots[slot]=id
    _records[id]=clean;revision+=1;return true

func remove(id: String) -> bool:
    if not _records.has(id):return false
    _records.erase(id);_slots[_slots.find(id)]="";revision+=1;return true

func snapshot() -> Dictionary:
    var lights: Array=[]
    for id in _slots:
        lights.append(_records[id].duplicate(true) if id!="" else {"position":[0.,0.,0.],"radius":1.,"power_rgb":[0.,0.,0.]})
    if lights.is_empty():lights.append({"position":[0.,0.,0.],"radius":1.,"power_rgb":[0.,0.,0.]})
    return {"schema":"lie-light-registry/1","revision":revision,"ids":_slots.duplicate(),"lights":lights,"capacity":CAPACITY,"units":"meters; relative linear RGB power"}
