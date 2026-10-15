extends "res://lie_wall06_shared_effect.gd"
const ContinuousShader=preload("res://shaders/lie_wall07_continuous.glsl")
const AssetCatalog=preload("res://lie_asset_catalog.gd")
var continuous_light: bool=true
var _groups:=PackedByteArray()
var asset_contract: Dictionary={}
func shader_resource() -> RDShaderFile:return ContinuousShader
func _init(size: int=720) -> void:
    super._init(size)
    asset_contract=AssetCatalog.validate(JSON.parse_string(FileAccess.get_file_as_string(capture_root()+"asset-contract.json")),catalog)
    if not asset_contract.get("ok",false):failure="Shared asset contract: "+str(asset_contract.get("error"));capture_loaded=false;return
    var proof: Variant=JSON.parse_string(FileAccess.get_file_as_string(capture_root()+"light-groups.json"))
    if not proof is Dictionary:failure="Light group proof missing";capture_loaded=false;return
    var path: String=capture_root()+"light-groups.bin"
    if proof.get("source_bank_sha256")!=catalog.get("sha256") or proof.get("source_light_sha256")!=catalog.get("lighting",{}).get("sha256") or FileAccess.get_sha256(path)!=proof.get("sha256"):failure="Light groups source identity";capture_loaded=false;return
    _groups=FileAccess.get_file_as_bytes(path)
    if _groups.size()!=16+872*16 or _groups.decode_u32(4)!=872:failure="Light group ABI";capture_loaded=false;return
    for node in range(872):
        var base: int=_groups.decode_u32(16+node*16);var count: int=_groups.decode_u32(20+node*16)
        if count<1 or count>9 or base>node or node>=base+count or base+count>872:failure="Light group range";capture_loaded=false;return
func _make_set() -> void:
    if not _buffers.has(21):
        _groups.encode_u32(0,1 if continuous_light else 0);_buffer(21,_groups.size(),_groups)
    super._make_set()
func set_continuous_light(value: bool) -> void:
    if continuous_light==value:return
    continuous_light=value
    if gpu_ready:RenderingServer.call_on_render_thread(func():
        _rd.buffer_update(_buffers[21],0,4,PackedInt32Array([1 if value else 0]).to_byte_array())
        _geometry_resident=PackedByteArray();_resident=PackedByteArray();_shade_dirty=true)
func cache_metrics() -> Dictionary:
    var result: Dictionary=super.cache_metrics();result["continuous_light"]=continuous_light;result["asset_contract"]=asset_contract;return result
