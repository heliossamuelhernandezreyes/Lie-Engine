extends RefCounted
## Optional immutable interval metadata. Missing/invalid data keeps full work.
static func open_bank(bank: Dictionary) -> Dictionary:
    var path: String=bank.path
    if not FileAccess.file_exists(path+"visibility-clusters.json"):return {}
    var meta: Variant=JSON.parse_string(FileAccess.get_file_as_string(path+"visibility-clusters.json"))
    if not meta is Dictionary or meta.get("schema")!="lie-visibility-clusters/2" or meta.get("bank_sha256")!=bank.catalog.sha256 or meta.get("cluster_size")!=64 or meta.get("stride")!=56 or meta.get("file")!="visibility-clusters.bin" or meta.get("indices_file")!="visibility-indices.bin" or not meta.get("entries") is Dictionary:return {}
    if not meta.get("bytes") is float and not meta.get("bytes") is int:return {}
    var size: int=int(meta.bytes)
    if size<56 or size>8*1024*1024 or size%56!=0:return {}
    var file:=FileAccess.open(path+"visibility-clusters.bin",FileAccess.READ)
    if file==null or file.get_length()!=size:return {}
    var bytes: PackedByteArray=file.get_buffer(size);file.close()
    var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
    if hash.finish().hex_encode()!=meta.get("sha256") or meta.entries.size()!=bank.index.entries.size():return {}
    var index_size: int=int(meta.get("indices_bytes",0))
    if index_size<4 or index_size%4!=0 or index_size>32*1024*1024:return {}
    file=FileAccess.open(path+"visibility-indices.bin",FileAccess.READ)
    if file==null or file.get_length()!=index_size:return {}
    var indices: PackedByteArray=file.get_buffer(index_size);file.close();hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(indices)
    if hash.finish().hex_encode()!=meta.get("indices_sha256"):return {}
    for key in bank.index.entries:
        var page: Dictionary=bank.index.entries[key];var entry: Variant=meta.entries.get(key)
        if not entry is Dictionary or entry.get("core_sha256")!=page.core_sha256 or entry.get("samples")!=page.count:return {}
        var first: int=int(entry.get("first",-1));var count: int=int(entry.get("clusters",0))
        if first<0 or count<1 or first+count>size/56:return {}
        var index_first: int=int(entry.get("index_first",-1))
        if index_first<0 or index_first+int(page.count)>index_size/4:return {}
        var offset: int=0
        for i in range(first,first+count):
            var at: int=i*56;var amount: int=bytes.decode_u32(at+4)
            if bytes.decode_u32(at)!=offset or amount<1 or amount>64:return {}
            offset+=amount
        if offset!=int(page.count):return {}
    return {"entries":meta.entries,"data":bytes,"indices":indices,"sha256":meta.sha256}

static func packet(instances: PackedByteArray,jobs: PackedByteArray,banks: Array) -> Dictionary:
    var result:=PackedByteArray();var indices:=PackedByteArray();var entries: PackedInt32Array=jobs.to_int32_array()
    for j in range(entries.size()/4):
        var at: int=j*4;var bank: int=int(instances.decode_float(entries[at+2]*96+68))
        var metadata: Dictionary=banks[bank].get("clusters",{})
        if metadata.is_empty():return {}
        var page: Dictionary=metadata.entries.get(str(entries[at])+":"+str(entries[at+1]),{})
        if page.is_empty():return {}
        var first: int=int(page.first);var count: int=int(page.clusters);var data: PackedByteArray=metadata.data
        var index_data: PackedByteArray=metadata.indices;var index_first: int=int(page.index_first)
        indices.append_array(index_data.slice(index_first*4,(index_first+entries[at+1])*4))
        for i in range(first,first+count):
            var offset: int=i*56
            result.append_array(PackedInt32Array([j,entries[at+3]+data.decode_u32(offset),data.decode_u32(offset+4),bank]).to_byte_array())
            result.append_array(data.slice(offset+8,offset+56))
        if result.size()>131072*64:return {}
    return {"plan":result,"indices":indices}
