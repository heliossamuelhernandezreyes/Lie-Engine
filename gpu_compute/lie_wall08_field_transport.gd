extends "res://lie_light_field_transport.gd"
## Wall adapter only: common transport owns no brick layout constants.
const SourceLoader=preload("res://lie_light_field_loader.gd")
const FIELD_ROOT="res://captures/liewall06/"
func configure(model: Dictionary) -> bool:
    var physical: Dictionary=model.duplicate(true)
    # One collision envelope encloses the visual surface; the explicit scanned
    # light-only occluders replace that envelope for transport, as in WALL06.
    physical["blockers"]=[]
    if _field_factors.is_empty():
        var source: Variant=JSON.parse_string(FileAccess.get_file_as_string(FIELD_ROOT+"light-model.json"))
        if not source is Dictionary:return false
        source["blockers"]=[]
        if not bind_sources(source,SourceLoader.load_sources(FIELD_ROOT)):
            failure="WALL08 common field source contract";return false
    return super.configure(physical)

func optical_metrics() -> Dictionary:
    var result: Dictionary=super.optical_metrics()
    result["graph"]="WALL06 rebuilt source geometry; common light-separated transport"
    return result
