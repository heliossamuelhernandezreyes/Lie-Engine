extends "res://lie_field_quality_transport.gd"
## Diagnostic labels only; all transport dispatches belong to the common field.
func _dispatch(commands: int,stage: int,threads: int,ping: int=0) -> void:
    if OS.get_environment("LIE_BRICK_TRACE")=="1":print("BRICK FIELD STAGE ",stage," threads ",threads)
    super._dispatch(commands,stage,threads,ping)
