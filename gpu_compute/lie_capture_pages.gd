extends RefCounted
## Metadata only at startup. SHA-locked source ranges are read on demand.
const Identity=preload("res://lie_asset_catalog.gd")
static func open_bank(path: String,expected: Dictionary) -> Dictionary:
    var c: Variant=JSON.parse_string(FileAccess.get_file_as_string(path+"catalog.json"));var index: Variant=JSON.parse_string(FileAccess.get_file_as_string(path+"pages.json"))
    if not c is Dictionary or not index is Dictionary or index.get("schema")!="lie-capture-page-index/1" or c.get("sha256")!=expected.get("sha256") or index.get("bank_sha256")!=c.get("sha256") or c.get("stride")!=80:return {}
    if not Identity.validate(JSON.parse_string(FileAccess.get_file_as_string(path+"asset-contract.json")),c).get("ok",false):return {}
    var optical: Dictionary=c.get("optical_normal_sidecar",{})
    if optical.get("sha256")!=expected.get("optical") or index.get("optical_sha256")!=expected.get("optical") or index.get("core_bytes")!=c.get("bytes") or index.get("optical_bytes")!=optical.get("bytes",0):return {}
    var file:=FileAccess.open(path+"library.bin",FileAccess.READ)
    if file==null or file.get_length()!=int(c.bytes):return {}
    file.close()
    if not optical.is_empty():
        if optical.get("schema")!="lie-optical-normal-sidecar/1" or optical.get("source_bank_sha256")!=c.sha256 or optical.get("stride")!=16 or optical.get("sample_count")!=c.sample_count:return {}
        var name: String=optical.get("file","")
        if name.is_empty() or name.get_file()!=name:return {}
        file=FileAccess.open(path+name,FileAccess.READ)
        if file==null or file.get_length()!=int(c.sample_count)*16:return {}
        file.close()
    var count: int=0
    for master in c.masters:
        for lod in range(c.masters[master].levels.size()):
            var level: Dictionary=c.masters[master].levels[lod];var key: String=str(int(level.start))+":"+str(int(level.count));var page: Variant=index.get("entries",{}).get(key)
            if not page is Dictionary or page.get("master")!=master or page.get("lod")!=lod or page.get("start")!=level.start or page.get("count")!=level.count or level.start<0 or level.count<1 or level.start+level.count>c.sample_count:return {}
            if not page.get("core_sha256") is String or page.core_sha256.length()!=64:return {}
            if not optical.is_empty() and (not page.get("optical_sha256") is String or page.optical_sha256.length()!=64):return {}
            for bound in [page.get("low"),page.get("high")]:
                if not bound is Array or bound.size()!=3:return {}
                for value in bound:
                    if not (value is int or value is float) or not is_finite(float(value)):return {}
            for k in range(3):
                if page.low[k]>=page.high[k]:return {}
            count+=1
    if count!=index.get("entries",{}).size():return {}
    return {"path":path,"catalog":c,"optical":optical,"index":index}
static func range_key(start: int,count: int) -> String:return str(start)+":"+str(count)
static func read_range(bank: Dictionary,start: int,count: int) -> Dictionary:
    var page: Variant=bank.index.entries.get(range_key(start,count))
    if not page is Dictionary:return {}
    var result: Dictionary={"page":page,"io_bytes":0}
    for kind in ["core","optical"]:
        if kind=="optical" and bank.optical.is_empty():result[kind]=PackedByteArray();continue
        var stride: int=80 if kind=="core" else 16;var file:=FileAccess.open(bank.path+("library.bin" if kind=="core" else bank.optical.file),FileAccess.READ)
        if file==null:return {}
        file.seek(start*stride);var bytes: PackedByteArray=file.get_buffer(count*stride);file.close()
        if bytes.size()!=count*stride:return {}
        var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
        if hash.finish().hex_encode()!=page[kind+"_sha256"]:return {}
        for value in bytes.to_float32_array():
            if not is_finite(value):return {}
        result[kind]=bytes;result.io_bytes+=bytes.size()
    return result
