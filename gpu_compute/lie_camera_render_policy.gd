extends RefCounted
## Explicit quality controls; output resolution remains independent.
const INTERNAL_SIZES = [720, 810, 900, 1080, 1440]
const BACKENDS = ["compute", "graphics"]

static func valid_size(value: Variant) -> bool:
	return value is int and value in INTERNAL_SIZES

static func valid_backend(value: Variant) -> bool:
	return value is String and value in BACKENDS

static func valid_values(values: Dictionary) -> String:
	if values.has("internal_resolution") and not valid_size(values["internal_resolution"]): return "internal_resolution"
	if values.has("raster_backend") and not valid_backend(values["raster_backend"]): return "raster_backend"
	return ""
