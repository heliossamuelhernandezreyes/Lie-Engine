extends RefCounted
## Explicit quality controls; output resolution remains independent.
const INTERNAL_SIZES = [720, 810, 900, 1080, 1440]
const BACKENDS = ["compute", "graphics"]

static func valid_size(value: Variant) -> bool:
	# Godot's JSON parser represents wire numbers as floats. Accept the exact
	# supported integral values, then canonicalize state for selectors/restores.
	if not (value is int or value is float): return false
	return value >= 720 and value <= 1440 and float(value) == floorf(float(value)) and int(value) in INTERNAL_SIZES

static func canonical_values(values: Dictionary) -> Dictionary:
	var result: Dictionary = values.duplicate(true)
	if result.has("internal_resolution"): result["internal_resolution"] = int(result["internal_resolution"])
	return result

static func valid_backend(value: Variant) -> bool:
	return value is String and value in BACKENDS

static func valid_values(values: Dictionary) -> String:
	if values.has("internal_resolution") and not valid_size(values["internal_resolution"]): return "internal_resolution"
	if values.has("raster_backend") and not valid_backend(values["raster_backend"]): return "raster_backend"
	return ""
