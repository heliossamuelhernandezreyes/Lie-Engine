extends "res://lie_field_quality_transport.gd"
## Captured wall is only a source adapter. All quality/visibility logic is common.
const SourceLoader=preload("res://lie_light_field_loader.gd")
const FIELD_ROOT="res://captures/liewall06/"
func configure(model: Dictionary) -> bool:
    var physical: Dictionary=model.duplicate(true);physical["blockers"]=[]
    if _field_factors.is_empty():
        var source: Variant=JSON.parse_string(FileAccess.get_file_as_string(FIELD_ROOT+"light-model.json"))
        if not source is Dictionary:return false
        source["blockers"]=[]
        if not bind_sources(source,SourceLoader.load_sources(FIELD_ROOT)):failure="Quality source contract";return false
    return super.configure(physical)
