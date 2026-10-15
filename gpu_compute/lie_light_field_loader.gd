extends RefCounted
## Verify immutable source packets before the common transport sees GPU data.
static func load_sources(root: String) -> Dictionary:
    var proof: Variant=JSON.parse_string(FileAccess.get_file_as_string(root+"light-field.json"))
    if not proof is Dictionary or proof.get("schema")!="lie-light-field-sources/1":return {}
    if proof.get("source_light_sha256")!=FileAccess.get_sha256(root+"light-model.json"):return {}
    var result: Dictionary={}
    for key in ["factors","outgoing","optics","planes","owners","boxes"]:
        var entry: Variant=proof.get("sources",{}).get(key)
        if not entry is Dictionary:return {}
        var name: String=entry.get("file","")
        if name.is_empty() or name.get_file()!=name:return {}
        var path: String=root+name
        if FileAccess.get_sha256(path)!=entry.get("sha256"):return {}
        var bytes: PackedByteArray=FileAccess.get_file_as_bytes(path)
        if bytes.size()!=int(entry.get("bytes",0)):return {}
        result[key]=bytes
    return result
