extends SceneTree
const Identity=preload("res://lie_sample_identity.gd")
var checks: int=0
var failed: bool=false
func check(value: bool,label: String) -> void:
    checks+=1
    if not value:failed=true;printerr("SAMPLE IDENTITY FAIL ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://captures/liewall06/catalog.json"))
    var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://captures/liewall06/asset-contract.json"))
    var identity=Identity.new();check(identity.configure(manifest,catalog),"verified source contract")
    for name in manifest["assets"]:
        var entry: Dictionary=manifest["assets"][name]
        for lod in range(entry["levels"].size()):
            var level: Dictionary=entry["levels"][lod];var address: Dictionary=identity.address(entry["asset_id"],lod,int(level["count"])-1,71)
            check(address["source_id"]==int(level["start"])+int(level["count"])-1 and address["byte_offset"]==address["source_id"]*80,"direct last-source address "+name+str(lod))
            check(address["instance_id"]==71 and identity.address(entry["asset_id"],lod,int(level["count"])).is_empty(),"instance identity and range boundary")
        check(identity.address(entry["asset_id"],-1,0).is_empty() and identity.address(entry["asset_id"],99,0).is_empty(),"invalid LOD rejected")
    check(identity.address("unknown",0,0).is_empty(),"unknown asset cannot alias resident data")
    var bad: Dictionary=manifest.duplicate(true);bad["bank_sha256"]="wrong";check(not identity.configure(bad,catalog) and identity.bank_sha256==catalog["sha256"],"invalid replacement is atomic")
    for counts in [[1,63,64,65],[4000,4000,151670],[240,9001]]:
        var jobs:=PackedInt32Array();var prefix: int=0
        for j in range(counts.size()):jobs.append_array(PackedInt32Array([prefix,counts[j],j,prefix]));prefix+=counts[j]
        var result: Dictionary=Identity.blocks(jobs.to_byte_array(),prefix,counts.size());var blocks: PackedInt32Array=result["bytes"].to_int32_array();var visits:=PackedInt32Array();visits.resize(prefix)
        for block in range(result["groups"]):
            var j: int=blocks[block*2];var begin: int=blocks[block*2+1]
            for lane in range(64):
                if begin+lane<int(counts[j]):visits[jobs[j*4+3]+begin+lane]+=1
        var exact: bool=true
        for n in visits:exact=exact and n==1
        check(exact and result["work"]==prefix,"every source dispatched exactly once")
        check(result["padding"]<64*counts.size(),"bounded padding independent of source count")
        var invalid: PackedByteArray=jobs.to_byte_array();invalid.encode_s32(0,-1)
        check(Identity.blocks(invalid,prefix,counts.size()).is_empty(),"invalid source mapping rejected")
    print("SAMPLE IDENTITY ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
