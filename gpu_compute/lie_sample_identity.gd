extends RefCounted
## Semantic identity is independent of GPU addresses and camera projections.
const Catalog=preload("res://lie_asset_catalog.gd")
var _assets: Dictionary={}
var bank_sha256: String=""
func configure(manifest: Dictionary,catalog: Dictionary) -> bool:
    if not Catalog.validate(manifest,catalog).get("ok",false):return false
    var incoming: Dictionary={}
    for entry in manifest["assets"].values():incoming[entry["asset_id"]]=entry.duplicate(true)
    _assets=incoming;bank_sha256=catalog["sha256"];return true
func address(asset_id: String,lod: int,sample_index: int,instance_id: int=0) -> Dictionary:
    if not _assets.has(asset_id) or lod<0 or sample_index<0 or instance_id<0:return {}
    var levels: Array=_assets[asset_id]["levels"]
    if lod>=levels.size() or sample_index>=int(levels[lod]["count"]):return {}
    var source_id: int=int(levels[lod]["start"])+sample_index
    return {"bank_sha256":bank_sha256,"asset_id":asset_id,"instance_id":instance_id,"source_id":source_id,"byte_offset":source_id*80,"stride":80}
static func blocks(jobs: PackedByteArray,reference_count: int,instance_count: int) -> Dictionary:
    if jobs.is_empty() or jobs.size()%16!=0 or reference_count<1 or instance_count<1:return {}
    var entries: PackedInt32Array=jobs.to_int32_array();var prefix: int=0;var result:=PackedInt32Array()
    for j in range(entries.size()/4):
        var at: int=entries[j*4];var count: int=entries[j*4+1];var owner: int=entries[j*4+2]
        if at<0 or count<1 or at+count>reference_count or owner<0 or owner>=instance_count or entries[j*4+3]!=prefix:return {}
        for local in range(0,count,64):result.append(j);result.append(local)
        prefix+=count
    return {"bytes":result.to_byte_array(),"groups":result.size()/2,"work":prefix,"padding":result.size()/2*64-prefix}
