extends "res://lie_surface_light_transport.gd"
## Only this adapter knows where the wall's verified immutable packets live.
const SourceLoader=preload("res://lie_light_field_loader.gd")
const FIELD_ROOT="res://captures/liewall06/"
func configure(model: Dictionary) -> bool:
    var physical: Dictionary=model.duplicate(true);physical["blockers"]=[]
    if _field_factors.is_empty():
        var source: Variant=JSON.parse_string(FileAccess.get_file_as_string(FIELD_ROOT+"light-model.json"))
        if not source is Dictionary:return false
        source["blockers"]=[]
        if not bind_sources(source,SourceLoader.load_sources(FIELD_ROOT)):
            failure="WALL09 surface source contract";return false
    return super.configure(physical)
