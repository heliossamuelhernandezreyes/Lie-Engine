extends RefCounted
## Mutable visibility is shared only for byte-identical source/scene domains.
## Render-thread dispatch/barriers serialize writes; metadata reads use a mutex.
const HEADER_BYTES: int=256
static var _entries: Dictionary={}
static var _mutex:=Mutex.new()
static var _allocations: int=0
static func acquire(rd: RenderingDevice,domain: String,count: int) -> Dictionary:
    if rd==null or domain.length()!=64 or count<1 or count>16000000:return {"ok":false}
    var key: String=str(rd.get_instance_id())+":"+domain
    _mutex.lock()
    if _entries.has(key):
        var entry: Dictionary=_entries[key]
        if entry["count"]!=count:_mutex.unlock();return {"ok":false}
        entry["references"]+=1;_mutex.unlock()
        return {"ok":true,"key":key,"rid":entry["rid"],"bytes":entry["bytes"],"uploaded":false}
    var size: int=HEADER_BYTES+count*12;var zero:=PackedByteArray();zero.resize(size)
    var rid: RID=rd.storage_buffer_create(size,zero)
    if not rid.is_valid():_mutex.unlock();return {"ok":false}
    _entries[key]={"rid":rid,"bytes":size,"count":count,"references":1,"device":rd.get_instance_id()};_allocations+=1
    _mutex.unlock();return {"ok":true,"key":key,"rid":rid,"bytes":size,"uploaded":true}
static func release(rd: RenderingDevice,key: String) -> void:
    _mutex.lock()
    if not _entries.has(key):_mutex.unlock();return
    var entry: Dictionary=_entries[key]
    if rd==null or entry["device"]!=rd.get_instance_id():_mutex.unlock();return
    entry["references"]-=1
    if entry["references"]==0:rd.free_rid(entry["rid"]);_entries.erase(key)
    _mutex.unlock()
static func metrics(rd: RenderingDevice) -> Dictionary:
    var bytes: int=0;var references: int=0;var groups: int=0
    _mutex.lock()
    for entry in _entries.values():
        if rd!=null and entry["device"]==rd.get_instance_id():bytes+=entry["bytes"];references+=entry["references"];groups+=1
    var allocations: int=_allocations;_mutex.unlock()
    return {"resident_bytes":bytes,"references":references,"domains":groups,"allocations_total":allocations,"scope":"source-reference/instance identity and scene; light positions validated on GPU"}
