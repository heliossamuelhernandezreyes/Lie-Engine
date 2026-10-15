extends RefCounted
## A resident world-surface derivation: view and light inputs are not its keys.
var _key:=PackedByteArray()
var builds: int=0
var reuses: int=0
func prepare(source_domain: String,assembly: PackedByteArray,recipe: PackedByteArray,schedule: PackedByteArray) -> bool:
    var key: PackedByteArray=source_domain.to_utf8_buffer()
    for packet in [assembly,recipe,schedule]:key.append_array(PackedInt64Array([packet.size()]).to_byte_array());key.append_array(packet)
    if key==_key:reuses+=1;return false
    _key=key;builds+=1;return true
func invalidate() -> void:_key=PackedByteArray()
func metrics() -> Dictionary:return {"builds":builds,"reuses":reuses,"scope":"source domain + instance assembly + geometry recipe + schedule; camera/light independent"}
