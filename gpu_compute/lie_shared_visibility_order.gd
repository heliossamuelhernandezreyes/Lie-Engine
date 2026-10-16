extends RefCounted
## Immutable query scheduling only; never a new asset or occlusion model.
static var _entries: Dictionary={}
static var _uploads: int=0
static func load_document(root: String,catalog: Dictionary,source: Dictionary) -> Dictionary:
    var proof: Variant=JSON.parse_string(FileAccess.get_file_as_string(root+"visibility-order.json"))
    if not proof is Dictionary or proof.get("schema")!="lie-visibility-order/1" or proof.get("file")!="visibility-order.bin":return {}
    if proof.get("source_bank_sha256")!=catalog["sha256"] or proof.get("source_references_sha256")!=source["packets"]["references"]["sha256"]:return {}
    var path: String=root+"visibility-order.bin"
    if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=proof.get("sha256"):return {}
    var bytes: PackedByteArray=FileAccess.get_file_as_bytes(path);var words: PackedInt32Array=bytes.to_int32_array();var levels: Dictionary={}
    if bytes.size()!=proof.get("bytes") or bytes.size()>12000000 or bytes.size()%4!=0 or proof.get("levels",[]).size()!=catalog["wall05"]["instance_jobs"].size():return {}
    var offset: int=0
    for index in range(proof["levels"].size()):
        var meta: Dictionary=proof["levels"][index];var jobs:=PackedInt32Array()
        for entry in catalog["wall05"]["instance_jobs"][index]:
            for value in entry:jobs.append(int(value))
        var hashing:=HashingContext.new();hashing.start(HashingContext.HASH_SHA256);hashing.update(jobs.to_byte_array())
        var count: int=jobs[-1]+jobs[-3]
        if hashing.finish().hex_encode()!=meta.get("jobs_sha256") or meta.get("key")!=jobs[1] or meta.get("offset")!=offset or meta.get("work")!=count or offset+count>words.size():return {}
        var seen:=PackedByteArray();seen.resize(count)
        for k in range(count):
            var id: int=words[offset+k]
            if id<0 or id>=count or seen[id]!=0:return {}
            seen[id]=1
        levels[jobs[1]]={"offset":offset,"work":count};offset+=count
    if offset!=words.size():return {}
    return {"bytes":bytes,"proof":proof,"levels":levels}
static func acquire(rd: RenderingDevice,document: Dictionary) -> Dictionary:
    var key: String=str(rd.get_instance_id())+":"+str(document["proof"]["sha256"])
    if _entries.has(key):
        var item: Dictionary=_entries[key];item["references"]+=1;return {"key":key,"rid":item["rid"],"bytes":item["bytes"],"uploaded":false}
    var bytes: PackedByteArray=document["bytes"];var rid: RID=rd.storage_buffer_create(bytes.size(),bytes)
    if not rid.is_valid():return {}
    _entries[key]={"rid":rid,"bytes":bytes.size(),"references":1};_uploads+=1
    return {"key":key,"rid":rid,"bytes":bytes.size(),"uploaded":true}
static func release(rd: RenderingDevice,key: String) -> void:
    if not _entries.has(key):return
    _entries[key]["references"]-=1
    if _entries[key]["references"]==0:rd.free_rid(_entries[key]["rid"]);_entries.erase(key)
static func metrics(key: String) -> Dictionary:
    var item: Dictionary=_entries.get(key,{})
    return {"resident_bytes":item.get("bytes",0),"references":item.get("references",0),"uploads_total":_uploads}
