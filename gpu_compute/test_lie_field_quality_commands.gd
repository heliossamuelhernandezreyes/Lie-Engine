extends SceneTree
const Quality=preload("res://lie_field_quality_model.gd")
const Transport=preload("res://lie_field_quality_transport.gd")
var checks: int=0
var failed: bool=false
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("QUALITY COMMAND FAIL ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/field-quality-reference.json"))
    var c: Dictionary=fixture.cases.paths_six;var sources: Dictionary={}
    for key in c.sources_hex:sources[key]=str(c.sources_hex[key]).hex_decode()
    var t=Transport.new()
    check(t.bind_sources(c.model,sources),"common immutable bank binding")
    check(t.configure(c.model),"quality configuration accepted")
    check(t._quality_desired.size()==32+(c.model.patches.size()+32)*16 and t._quality_edge_tail.size()==sources.factors.decode_u32(4)*2*16,"mutable policy excludes immutable endpoint table")
    var before: PackedByteArray=t._quality_desired.duplicate()
    check(not t.set_field_quality({"angular_sectors":2}),"invalid sector capacity rejected")
    check(t._quality_desired==before,"rejection leaves desired bytes unchanged")
    var box: Array=[[[.35,-.1,.35],[.65,.1,.65]]]
    check(t.set_dynamic_occluders(box,0,1),"visibility revision commits")
    var blocked: PackedByteArray=t._quality_desired.duplicate()
    check(not t.set_dynamic_occluders([],0,2),"stale visibility revision rejected")
    check(t._quality_desired==blocked,"stale command has no partial mutation")
    check(t.set_dynamic_occluders([],1,2),"visibility restoration commits")
    check(t._quality_desired.decode_u32(8)==0 and t._pending.get("force",false),"restoration invalidates cached transport")
    var malformed: Dictionary=c.model.duplicate(true);malformed["field_quality"]={"reference_area":0}
    before=t._quality_desired.duplicate()
    check(not t.configure(malformed) and t._quality_desired==before,"bad configure is atomic")
    for q in [{"area_budget":1},{"roughness_split":NAN},{"dynamic_occluders":[[[0,0,0],[0,1,1]]]},{"visibility_revision":-1}]:
        check(not Quality.valid(q),"malformed policy rejected")
    check(Quality.packet([1.],{}).size()==32+33*16,"quality ABI capacity")
    var from_json: Variant=JSON.parse_string('{"angular_sectors":6,"visibility_revision":2}')
    check(Quality.packet([1.],from_json).size()==32+33*16,"JSON numeric policy survives parser float conversion")
    check(not Quality.valid({"angular_sectors":1.5}) and not Quality.integer_value(true,0,1),"fractional and boolean revisions rejected")
    malformed=c.model.duplicate(true);malformed["field_quality"]={"visibility_revision":0}
    before=t._quality_desired.duplicate()
    check(not t.configure(malformed) and t._quality_desired==before,"full configure cannot replay stale visibility")
    var last: PackedByteArray=Quality.packet([1.],{"visibility_revision":4294967295})
    check(not last.is_empty() and last.decode_u32(12)==4294967295,"uint32 revision ABI survives maximum value")
    check(Quality.with_edges(Quality.packet([.1,.1,.1,.1,.1,.1],{}),sources.factors,sources.outgoing)==str(c.quality_hex).hex_decode(),"compiled edge packet matches independent float64 encoder")
    var bad_graph: PackedByteArray=sources.factors.duplicate();bad_graph.encode_u32(4,4294967295)
    check(Quality.with_edges(Quality.packet([.1,.1,.1,.1,.1,.1],{}),bad_graph,sources.outgoing).is_empty(),"oversized edge count rejected before allocation")
    var external: Dictionary={"dynamic_occluders":[[[.35,-.1,.35],[.65,.1,.65]]],"visibility_revision":3}
    check(t.set_field_quality(external),"caller-owned policy accepted")
    before=t._quality_desired.duplicate();external.dynamic_occluders[0][0][0]=.1
    check(t._quality_desired==before and t.optical_metrics().quality.policy.dynamic_occluders[0][0][0]==.35,"caller mutation cannot alter a published snapshot")
    print("QUALITY COMMAND ","FAIL" if failed else "PASS"," ",checks)
    t=null;quit(1 if failed else 0)
