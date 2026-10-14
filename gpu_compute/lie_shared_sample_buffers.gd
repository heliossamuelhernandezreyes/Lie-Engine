extends RefCounted
## Render-thread-only leases for immutable sample banks on the SAME RD.
## Every camera/pose owns its writable buffers; only source data are shared.
static var _entries: Dictionary={}
static var _uploads: int=0

static func acquire(rd: RenderingDevice,data: PackedByteArray,sha256: String,stride: int) -> Dictionary:
    if rd==null or data.is_empty() or stride<1 or data.size()%stride!=0 or sha256.length()!=64:
        return {"ok":false,"error":"sample_buffer_contract"}
    var hashing:=HashingContext.new();hashing.start(HashingContext.HASH_SHA256);hashing.update(data)
    if hashing.finish().hex_encode()!=sha256:return {"ok":false,"error":"sample_buffer_sha256"}
    var key: String=str(rd.get_instance_id())+":"+sha256+":"+str(stride)
    if _entries.has(key):
        var entry: Dictionary=_entries[key]
        if entry["bytes"]!=data.size() or not entry["rid"].is_valid():return {"ok":false,"error":"sample_buffer_identity"}
        entry["references"]+=1
        return {"ok":true,"key":key,"rid":entry["rid"],"bytes":entry["bytes"],"uploaded":false,"cpu_data":entry["data"]}
    var rid: RID=rd.storage_buffer_create(data.size(),data)
    if not rid.is_valid():return {"ok":false,"error":"sample_buffer_allocation"}
    _entries[key]={"rid":rid,"bytes":data.size(),"references":1,"device":rd.get_instance_id(),"sha256":sha256,"data":data}
    _uploads+=1
    return {"ok":true,"key":key,"rid":rid,"bytes":data.size(),"uploaded":true,"cpu_data":data}

static func release(rd: RenderingDevice,key: String) -> bool:
    if rd==null or not _entries.has(key) or _entries[key]["device"]!=rd.get_instance_id():return false
    var entry: Dictionary=_entries[key]
    entry["references"]-=1
    if entry["references"]==0:
        if entry["rid"].is_valid():rd.free_rid(entry["rid"])
        _entries.erase(key)
    return true

static func metrics(rd: RenderingDevice) -> Dictionary:
    var bytes: int=0;var references: int=0;var banks: int=0
    for entry in _entries.values():
        if rd!=null and entry["device"]==rd.get_instance_id():
            bytes+=entry["bytes"];references+=entry["references"];banks+=1
    return {"unique_resident_bytes":bytes,"live_banks":banks,"live_references":references,
        "physical_uploads_total":_uploads,"scope":"immutable sample buffers on this RenderingDevice, not engine/process RAM"}
