extends "res://lie_wall02_micro_transport.gd"
## Same LIE11 real RGB flux, source patches, two bounces, 96 light-only boxes.
## WALL04-specific physics fix: a patch INSIDE the coarse opaque wall core
## cannot shadow itself when casting a direct-ray toward the real light.
const WALL04_TRANSPORT: RDShaderFile=preload("res://shaders/lie_wall04_transport.glsl")
const SPARSE_TRANSPORT: RDShaderFile=preload("res://shaders/lie_wall04_transport_sparse.glsl")
var sparse_transport: bool=true
var _source_packet:=PackedByteArray()
var _source_geometry:=PackedByteArray()
var _graph_metadata: Dictionary={}

func _init(use_sparse: bool=true) -> void:
    super._init();sparse_transport=use_sparse
    cache_static_transport=true;profile_transport=true

func _transport_file() -> RDShaderFile:
    return SPARSE_TRANSPORT if sparse_transport else WALL04_TRANSPORT

func factor_input_bytes(model: Dictionary) -> PackedByteArray:
    var root: String="res://captures/liewall04/"
    if _source_packet.is_empty():
        var catalog: Variant=JSON.parse_string(FileAccess.get_file_as_string(root+"catalog.json"))
        var proof: Variant=JSON.parse_string(FileAccess.get_file_as_string(root+"indirect_factors.json"))
        var source: Variant=JSON.parse_string(FileAccess.get_file_as_string(root+"light-model.json"))
        if not catalog is Dictionary or not proof is Dictionary or not source is Dictionary:return PackedByteArray()
        if proof.get("patches")!=872 or proof.get("input_wall_sha256")!=catalog.get("sha256") or proof.get("input_light_sha256")!=catalog.get("lighting",{}).get("sha256"):return PackedByteArray()
        source["blockers"]=[]
        _source_geometry=Model.transfer_geometry_key(source)
        var path: String=root+("indirect_sparse.bin" if sparse_transport else "indirect_factors.bin")
        var expected_sha: String=str(proof.get("sha256",""))
        var expected_bytes: int=872*872*4
        if sparse_transport:
            var meta: Variant=JSON.parse_string(FileAccess.get_file_as_string(root+"indirect_sparse.json"))
            if not meta is Dictionary or meta.get("schema")!="lie-receiver-csr-f32/1" or meta.get("patches")!=872 or meta.get("dense_sha256")!=expected_sha or meta.get("input_wall_sha256")!=catalog.get("sha256") or meta.get("input_light_sha256")!=proof.get("input_light_sha256"):return PackedByteArray()
            _graph_metadata=meta;expected_sha=str(meta.get("sha256",""));expected_bytes=int(meta.get("bytes",0))
        else:_graph_metadata={"bytes":expected_bytes,"dense_bytes":expected_bytes,"edges":872*872}
        if not FileAccess.file_exists(path) or expected_bytes<1 or FileAccess.get_sha256(path)!=expected_sha:return PackedByteArray()
        var bytes: PackedByteArray=FileAccess.get_file_as_bytes(path)
        if bytes.size()!=expected_bytes:return PackedByteArray()
        if sparse_transport and (bytes.decode_u32(0)!=872 or bytes.decode_u32(4)!=int(_graph_metadata["edges"]) or bytes.decode_u32(8)!=4 or bytes.decode_u32(12)!=877):return PackedByteArray()
        _source_packet=bytes
    if Model.transfer_geometry_key(model)!=_source_geometry:
        failure="WALL04 patch geometry changed: rebuild the source visibility graph"
        return PackedByteArray()
    return _source_packet

func transport_metrics() -> Dictionary:
    var result: Dictionary=super.transport_metrics()
    result.merge({"backend":"receiver_csr" if sparse_transport else "dense",
        "graph":_graph_metadata.duplicate(true),"source_factor_rebuilt_in_runtime":false},true)
    return result

## Replace ONLY the precomputed LIE11 indirect visibility graph. The
## legacy giant wall core incorrectly blocked physical bounce paths among
## distinct source bricks. Radiometry, powers, node code ABI and 2 bounce
## generations remain the ORIGINAL LIE11 GPU implementation.
func configure(model: Dictionary) -> bool:
    var physical: Dictionary=model.duplicate(true)
    physical["blockers"]=[] # Direct shadowing is handled by 96 scanned-brick AABBs.
    var n: int=(physical.get("patches",[]) as Array).size()
    if n!=872:
        failure="WALL04 872-patch source-correct indirect visibility matrix missing"
        return false
    return super.configure(physical)
