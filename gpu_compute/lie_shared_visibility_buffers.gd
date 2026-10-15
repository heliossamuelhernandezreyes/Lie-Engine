extends RefCounted
## Render-thread leases for immutable BLAS packets, independent of scene TLAS.
static var _entries: Dictionary={}
static var _uploads: int=0
static var _mutex:=Mutex.new()
static func _sha(bytes: PackedByteArray) -> String:
    var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(bytes);return context.finish().hex_encode()
static func acquire(rd: RenderingDevice,nodes: PackedByteArray,leaves: PackedByteArray,node_sha: String,leaf_sha: String) -> Dictionary:
    if rd==null or nodes.is_empty() or nodes.size()%32!=0 or leaves.is_empty() or leaves.size()%4!=0:return {"ok":false}
    if _sha(nodes)!=node_sha or _sha(leaves)!=leaf_sha:return {"ok":false}
    var key: String=str(rd.get_instance_id())+":"+node_sha+":"+leaf_sha
    _mutex.lock()
    if _entries.has(key):
        var entry: Dictionary=_entries[key];entry["references"]+=1
        _mutex.unlock();return {"ok":true,"key":key,"nodes":entry["nodes"],"leaves":entry["leaves"],"bytes":entry["bytes"],"uploaded":false}
    var a: RID=rd.storage_buffer_create(nodes.size(),nodes);var b: RID=rd.storage_buffer_create(leaves.size(),leaves)
    if not a.is_valid() or not b.is_valid():
        if a.is_valid():rd.free_rid(a)
        if b.is_valid():rd.free_rid(b)
        _mutex.unlock();return {"ok":false}
    _entries[key]={"nodes":a,"leaves":b,"bytes":nodes.size()+leaves.size(),"references":1,"device":rd.get_instance_id()};_uploads+=1
    _mutex.unlock();return {"ok":true,"key":key,"nodes":a,"leaves":b,"bytes":nodes.size()+leaves.size(),"uploaded":true}
static func release(rd: RenderingDevice,key: String) -> void:
    _mutex.lock()
    if not _entries.has(key):_mutex.unlock();return
    var entry: Dictionary=_entries[key]
    if entry["device"]!=rd.get_instance_id():_mutex.unlock();return
    entry["references"]-=1
    if entry["references"]==0:
        rd.free_rid(entry["nodes"]);rd.free_rid(entry["leaves"]);_entries.erase(key)
    _mutex.unlock()
static func metrics(rd: RenderingDevice) -> Dictionary:
    var bytes: int=0;var references: int=0;var groups: int=0
    _mutex.lock()
    for entry in _entries.values():
        if rd!=null and entry["device"]==rd.get_instance_id():bytes+=entry["bytes"];references+=entry["references"];groups+=1
    _mutex.unlock();return {"shared_blas_bytes":bytes,"groups":groups,"references":references,"uploads_total":_uploads,"scope":"immutable source visibility; scene hierarchy and writable caches excluded"}
