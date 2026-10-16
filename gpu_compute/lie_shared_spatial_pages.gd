extends RefCounted
## Immutable local-space pages. Scene instances never duplicate this RID.
static var _entries: Dictionary={}
static var _uploads: int=0
static var _mutex:=Mutex.new()
static func load_document(root: String,catalog: Dictionary,source_proof: Dictionary) -> Dictionary:
    var proof: Variant=JSON.parse_string(FileAccess.get_file_as_string(root+"spatial-pages.json"))
    if not proof is Dictionary or proof.get("schema")!="lie-spatial-pages/1" or proof.get("file")!="spatial-pages.bin":return {}
    if proof.get("source_bank_sha256")!=catalog.get("sha256") or proof.get("source_blas_sha256")!=source_proof.get("packets",{}).get("nodes",{}).get("sha256"):return {}
    var path: String=root+"spatial-pages.bin"
    if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=proof.get("sha256"):return {}
    var bytes: PackedByteArray=FileAccess.get_file_as_bytes(path);var words: PackedInt32Array=bytes.to_int32_array()
    if bytes.size()!=proof.get("bytes") or bytes.size()>32*1024*1024 or words.size()<8:return {}
    if words[0]!=0x4c504731 or words[1]!=1 or words[2]!=source_proof.get("roots",[]).size() or words[3]<1 or words[3]>1000000 or words[4]!=8 or words[5]!=8+words[3] or words[6]!=words.size():return {}
    if words[5]+words[2]*16>words.size():return {}
    for index in range(words[2]):
        var at: int=words[5]+index*16;var root_proof: Dictionary=source_proof["roots"][index]
        var node: int=int(root_proof["root"])
        if node<0 or node>=words[3] or words[8+node]!=index+1 or words[at+15]!=node or words[at+13]!=int(root_proof["start"]) or words[at+14]!=int(root_proof["count"]):return {}
        var dims:=Vector3i(words[at+3],words[at+7],words[at+8]);var cells: int=dims.x*dims.y*dims.z
        if dims.x<1 or dims.y<1 or dims.z<1 or dims.x>64 or dims.y>64 or dims.z>64 or cells!=words[at+12]:return {}
        for axis in range(3):
            var low: float=bytes.decode_float((at+axis)*4);var high: float=bytes.decode_float((at+4+axis)*4)
            if not is_finite(low) or not is_finite(high) or high<=low:return {}
        var offsets: int=words[at+9];var ids: int=words[at+10];var count: int=words[at+11]
        if offsets<words[5]+words[2]*16 or offsets+cells+1>words.size() or ids<offsets+cells+1 or count<1 or ids+count>words.size():return {}
        if words[offsets]!=0 or words[offsets+cells]!=count:return {}
        for cell in range(cells):
            if words[offsets+cell]<0 or words[offsets+cell]>words[offsets+cell+1]:return {}
        for k in range(count):
            var source: int=words[ids+k]
            if source<words[at+13] or source>=words[at+13]+words[at+14] or source>=int(catalog["sample_count"]):return {}
    return {"bytes":bytes,"proof":proof}
static func acquire(rd: RenderingDevice,document: Dictionary) -> Dictionary:
    if rd==null or document.is_empty():return {"ok":false}
    var key: String=str(rd.get_instance_id())+":"+str(document["proof"]["sha256"])
    _mutex.lock()
    if _entries.has(key):
        var entry: Dictionary=_entries[key];entry["references"]+=1
        _mutex.unlock();return {"ok":true,"key":key,"rid":entry["rid"],"bytes":entry["bytes"],"uploaded":false}
    var bytes: PackedByteArray=document["bytes"];var rid: RID=rd.storage_buffer_create(bytes.size(),bytes)
    if not rid.is_valid():_mutex.unlock();return {"ok":false}
    _entries[key]={"rid":rid,"bytes":bytes.size(),"references":1,"device":rd.get_instance_id()};_uploads+=1
    _mutex.unlock();return {"ok":true,"key":key,"rid":rid,"bytes":bytes.size(),"uploaded":true}
static func release(rd: RenderingDevice,key: String) -> void:
    _mutex.lock()
    if not _entries.has(key):_mutex.unlock();return
    var entry: Dictionary=_entries[key]
    if entry["device"]!=rd.get_instance_id():_mutex.unlock();return
    entry["references"]-=1
    if entry["references"]==0:rd.free_rid(entry["rid"]);_entries.erase(key)
    _mutex.unlock()
static func metrics(rd: RenderingDevice) -> Dictionary:
    var bytes: int=0;var references: int=0;var groups: int=0
    _mutex.lock()
    for entry in _entries.values():
        if rd!=null and entry["device"]==rd.get_instance_id():bytes+=entry["bytes"];references+=entry["references"];groups+=1
    _mutex.unlock();return {"resident_bytes":bytes,"references":references,"domains":groups,"uploads_total":_uploads}
