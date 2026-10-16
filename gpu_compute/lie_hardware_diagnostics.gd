extends RefCounted
## No native sampling until an explicit probe/begin request.
var _native: Object
func _init() -> void:
    if ClassDB.class_exists("LieGPUProbe"):_native=ClassDB.instantiate("LieGPUProbe")
func missing() -> Dictionary:return {"available":false,"native_extension":false,"reason":"native_extension_missing"}
func probe() -> Dictionary:return _native.probe() if _native!=null else missing()
func begin() -> Dictionary:return _native.begin() if _native!=null else missing()
func end() -> Dictionary:return _native.end() if _native!=null else missing()
func telemetry() -> Dictionary:return _native.telemetry() if _native!=null else missing()
func release_counters() -> void:
    if _native!=null:_native.release_counters()
