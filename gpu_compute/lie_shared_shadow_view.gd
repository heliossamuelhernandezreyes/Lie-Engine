extends RefCounted
## Immutable shadow-only view; original sample IDs and bits, one upload/device.
static var _entries: Dictionary={}
static var _mutex:=Mutex.new()
static func load_document(root: String,catalog: Dictionary) -> Dictionary:
    var proof: Variant=JSON.parse_string(FileAccess.get_file_as_string(root+"shadow-view.json"))
    if not proof is Dictionary or proof.get("schema")!="lie-shadow-view/1" or proof.get("file")!="shadow-view.bin" or proof.get("source_bank_sha256")!=catalog.get("sha256"):return {}
    var path: String=root+"shadow-view.bin"
    if proof.get("stride")!=32 or proof.get("original_stride")!=80 or int(proof.get("source_count",0))*80!=int(catalog.get("bytes",0)):return {}
    if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=proof.get("sha256"):return {}
    var bytes: PackedByteArray=FileAccess.get_file_as_bytes(path)
    if bytes.size()!=proof.get("bytes") or bytes.size()!=int(proof["source_count"])*32:return {}
    return {"proof":proof,"bytes":bytes}
static func acquire(rd: RenderingDevice,document: Dictionary) -> Dictionary:
    var key: String=str(rd.get_instance_id())+":"+document["proof"]["source_bank_sha256"]+":"+document["proof"]["sha256"]
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
