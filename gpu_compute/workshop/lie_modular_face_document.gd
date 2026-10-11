extends "res://workshop/lie_face_document.gd"
## One compatible facial family; randomization uses a local seeded generator.
func _init() -> void:
    state["nose_index"]=1.0
func _limits() -> Dictionary:
    var limits: Dictionary=LIMITS.duplicate(true);limits["nose_index"]=[0,3];return limits
func _master() -> String:
    return "lie-modular-face24"
func _directory() -> String:
    return "user://face24"
func validate(candidate: Variant) -> String:
    var error: String=super.validate(candidate)
    if error!="":return error
    if candidate["nose_index"]!=floorf(candidate["nose_index"]):return "discrete_nose_index"
    return ""
func dispatch(request: Variant) -> Dictionary:
    if request is Dictionary and request.get("op")=="randomize":
        var seed_value: Variant=request.get("seed")
        if not (seed_value is int or seed_value is float) or not is_finite(float(seed_value)) or seed_value!=floorf(seed_value) or seed_value<0 or seed_value>2147483647:return {"ok":false,"error":"seed","revision":revision}
        var generator:=RandomNumberGenerator.new();generator.seed=int(seed_value)
        var command: Dictionary={"op":"set_values","values":{"nose_index":generator.randi_range(1,3)}}
        if request.has("expected_revision"):command["expected_revision"]=request["expected_revision"]
        return super.dispatch(command)
    return super.dispatch(request)
