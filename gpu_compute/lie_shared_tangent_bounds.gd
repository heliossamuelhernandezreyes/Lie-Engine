extends RefCounted
## Render-thread leases for immutable refitted node bounds, no duplicate leaves.
static var _entries: Dictionary={}
static var _mutex:=Mutex.new()
static func load_document(root: String,catalog: Dictionary,source: Dictionary,original: PackedByteArray) -> Dictionary:
    var proof: Variant=JSON.parse_string(FileAccess.get_file_as_string(root+"tangent-bounds.json"))
    if not proof is Dictionary or proof.get("schema")!="lie-tangent-bounds/1" or proof.get("file")!="tangent-bounds.bin" or proof.get("source_bank_sha256")!=catalog.get("sha256"):return {}
    for key in ["nodes","leaves","scene"]:
        if proof.get("original_"+key+"_sha256")!=source["packets"][key]["sha256"]:return {}
    var path: String=root+"tangent-bounds.bin"
    if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=proof.get("sha256"):return {}
    var bytes: PackedByteArray=FileAccess.get_file_as_bytes(path)
    if bytes.size()!=original.size() or bytes.size()!=proof.get("bytes") or bytes.size()!=int(proof.get("nodes",0))*32:return {}
    for at in range(0,bytes.size(),32):
        if bytes.decode_u32(at+12)!=original.decode_u32(at+12) or bytes.decode_u32(at+28)!=original.decode_u32(at+28):return {}
        for axis in range(3):
            var low: float=bytes.decode_float(at+axis*4);var high: float=bytes.decode_float(at+16+axis*4)
            if not is_finite(low) or not is_finite(high) or low>high or low<original.decode_float(at+axis*4) or high>original.decode_float(at+16+axis*4):return {}
    return {"proof":proof,"bytes":bytes}
static func acquire(rd: RenderingDevice,document: Dictionary) -> Dictionary:
    var key: String=str(rd.get_instance_id())+":"+document["proof"]["sha256"]
    _mutex.lock()
    if _entries.has(key):
        var entry: Dictionary=_entries[key];entry["references"]+=1;_mutex.unlock();return {"key":key,"rid":entry["rid"],"bytes":entry["bytes"]}
    var raw: PackedByteArray=document["bytes"];var rid: RID=rd.storage_buffer_create(raw.size(),raw)
    if not rid.is_valid():_mutex.unlock();return {}
    _entries[key]={"rid":rid,"bytes":raw.size(),"references":1,"device":rd.get_instance_id()}
    _mutex.unlock();return {"key":key,"rid":rid,"bytes":raw.size()}
static func release(rd: RenderingDevice,key: String) -> void:
    _mutex.lock()
    if _entries.has(key) and _entries[key]["device"]==rd.get_instance_id():
        _entries[key]["references"]-=1
        if _entries[key]["references"]==0:rd.free_rid(_entries[key]["rid"]);_entries.erase(key)
    _mutex.unlock()
