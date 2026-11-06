extends SceneTree
## Diagnostic prefixes preserve failure; they never replace full acceptance.
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var lab=load("res://lie_brick_reference_lab.tscn").instantiate();lab.ui_enabled=false;root.add_child(lab)
    for i in range(20):await process_frame
    var field_only: bool=OS.get_environment("LIE_BRICK_FIELD_ONLY")=="1"
    if field_only:lab.transport.request_readback()
    else:lab.effect.request_readback()
    for i in range(180):
        await process_frame
        var data: Dictionary=lab.transport.readback() if field_only else lab.effect.readback()
        if not data.is_empty():
            print("BRICK PREFIX PASS field_only=",field_only," max_stage=",OS.get_environment("LIE_BRICK_MAX_STAGE"))
            lab.queue_free()
            for j in range(8):await process_frame
            quit(0);return
    printerr("BRICK PREFIX readback failed");lab.queue_free();await process_frame;quit(1)
