extends RefCounted
static func _bounds(bytes: PackedByteArray,at: int) -> bool:
    for k in range(3):
        var low: float=bytes.decode_float(at+k*4);var high: float=bytes.decode_float(at+16+k*4)
        if not is_finite(low) or not is_finite(high) or low>high:return false
    return true
static func _hierarchy(nodes: PackedByteArray,refs: PackedByteArray,max_id: int,leaf_limit: int) -> bool:
    var count: int=nodes.size()/32
    if count<1:return false
    for i in range(count):
        var at: int=i*32;var escape: int=nodes.decode_u32(at+12);var leaf: int=nodes.decode_u32(at+28)
        if not _bounds(nodes,at) or escape<=i or escape>count:return false
        if leaf==0xffffffff:
            if escape<=i+1:return false
            continue
        if leaf*4+4>refs.size():return false
        var n: int=refs.decode_u32(leaf*4)
        if n<1 or n>leaf_limit or (leaf+n+1)*4>refs.size():return false
        for k in range(n):
            if refs.decode_u32((leaf+1+k)*4)>=max_id:return false
    return true
static func load_packets(root: String,catalog: Dictionary) -> Dictionary:
    var proof: Variant=JSON.parse_string(FileAccess.get_file_as_string(root+"surface-source.json"))
    if not proof is Dictionary or proof.get("schema")!="lie-source-surface/1" or proof.get("source_bank_sha256")!=catalog.get("sha256") or proof.get("source_samples")!=catalog.get("sample_count"):return {}
    var packets: Dictionary={}
    var names: Dictionary={"references":"surface-refs.bin","nodes":"surface-bvh.bin","leaves":"surface-leaves.bin","scene":"surface-scene.bin"}
    for key in names:
        var meta: Dictionary=proof.get("packets",{}).get(key,{})
        var path: String=root+names[key]
        if meta.get("file")!=names[key] or not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=meta.get("sha256"):return {}
        var bytes: PackedByteArray=FileAccess.get_file_as_bytes(path)
        if bytes.size()!=meta.get("bytes") or bytes.size()<4 or bytes.size()>64*1024*1024:return {}
        packets[key]=bytes
    var references: PackedByteArray=packets["references"]
    if references.size()!=proof.get("reference_bytes") or references.size()%4!=0:return {}
    for source in references.to_int32_array():
        if source<0 or source>=int(catalog["sample_count"]):return {}
    if not _hierarchy(packets["nodes"],packets["leaves"],int(catalog["sample_count"]),8):return {}
    var scene: PackedByteArray=packets["scene"]
    if scene.size()<16 or scene.size()%16!=0:return {}
    var nodes: int=scene.decode_u32(0);var refs: int=scene.decode_u32(4);var instances: int=scene.decode_u32(12);var offset: int=scene.decode_u32(8)
    if nodes<1 or instances<1 or instances>1024 or instances!=proof.get("instances") or refs!=4+nodes*8 or offset<refs or (offset+instances*16)*4!=scene.size():return {}
    if not _hierarchy(scene.slice(16,refs*4),scene.slice(refs*4,offset*4),instances,1):return {}
    for i in range(instances):
        var at: int=(offset+i*16)*4
        for k in range(12):
            if not is_finite(scene.decode_float(at+k*4)):return {}
        if scene.decode_u32(at+48)*32>=packets["nodes"].size():return {}
    packets["proof"]=proof;return packets
