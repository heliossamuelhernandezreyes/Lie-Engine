extends SceneTree
const Registry=preload("res://lie_light_registry.gd")
const Field=preload("res://lie_light_field_transport.gd")
const World=preload("res://lie_light_world.gd")
const Emitter=preload("res://lie_point_emitter_3d.gd")
var checks: int=0
var failed: bool=false
func check(value: bool,label: String) -> void:
    checks+=1
    if not value:failed=true;printerr("FIELD CONTRACT FAIL ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var registry=Registry.new();var code: Dictionary={"position":[0.,1.,2.],"radius":6.,"power_rgb":[1.,.5,.2]}
    check(registry.upsert("warm",code),"register stable ID")
    var snapshot: Dictionary=registry.snapshot();code["power_rgb"][0]=20.
    check(registry.snapshot()["lights"][0]["power_rgb"][0]==1.,"caller mutation cannot alter residency")
    snapshot["lights"][0]["power_rgb"][0]=40.
    check(registry.snapshot()["lights"][0]["power_rgb"][0]==1.,"snapshots are immutable copies")
    check(registry.upsert("cool",code) and registry.snapshot()["ids"]==["warm","cool"],"second source keeps separate slot")
    var revision: int=registry.revision
    check(not registry.upsert("bad",{"position":[NAN,0,0],"radius":1.,"power_rgb":[1,1,1]}) and registry.revision==revision,"invalid update is atomic")
    for i in range(6):check(registry.upsert(str(i),code),"bounded source capacity "+str(i))
    check(not registry.upsert("overflow",code),"ninth source explicitly rejected")
    check(registry.remove("warm") and registry.snapshot()["lights"][0]["power_rgb"]==[0.,0.,0.],"removed slot contributes zero")
    check(registry.upsert("replacement",code) and registry.snapshot()["ids"][0]=="replacement","vacant slot can be reused with a new ID")
    var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/light-field-reference.json"))
    var case: Dictionary=fixture["cases"]["two_colored_lights"];var packets: Dictionary={}
    for key in case["sources_hex"]:packets[key]=str(case["sources_hex"][key]).hex_decode()
    var field=Field.new();check(field.bind_sources(case["model"],packets),"common source ABI and graph transpose")
    check(field.configure(case["model"]),"generic three-surface scene accepted")
    var changed: Dictionary=case["model"].duplicate(true);changed["patches"][0]["position"][0]=1.
    check(field.factor_input_bytes(changed).is_empty(),"changed geometry cannot reuse stale transport")
    var wrong: Dictionary=packets.duplicate(true);wrong["owners"].encode_u32(0,12)
    check(not Field.new().bind_sources(case["model"],wrong),"owner outside visibility bank rejected")
    wrong=packets.duplicate(true);wrong["outgoing"].encode_float(4*(3+5)+4,.9)
    check(not Field.new().bind_sources(case["model"],wrong),"normalization and gather graph mismatch rejected")
    wrong=packets.duplicate(true);wrong["optics"].encode_float(16+20,1.)
    check(not Field.new().bind_sources(case["model"],wrong),"unsupported transmitted graph rejected")
    var world=World.new();root.add_child(world);var emitter=Emitter.new();emitter.light_id="scene";world.add_child(emitter)
    emitter.position=Vector3(1,2,3);check(world.refresh() and world.registry.snapshot()["lights"][0]["position"]==[1.,2.,3.],"scene transform feeds source code")
    world.position=Vector3(10,20,30);check(world.refresh() and world.registry.snapshot()["lights"][0]["position"]==[1.,2.,3.],"world-local metric frame survives translation")
    var duplicate=Emitter.new();duplicate.light_id="scene";world.add_child(duplicate);revision=world.registry.revision
    check(not world.refresh() and world.registry.revision==revision,"duplicate scene IDs rejected atomically")
    duplicate.free();emitter.enabled=false;check(world.refresh() and world.registry.snapshot()["lights"][0]["power_rgb"]==[0.,0.,0.],"scene source disables without changing ID")
    world.scale=Vector3(2,1,1);check(not world.refresh(),"ambiguous world scale rejected")
    world.free()
    print("FIELD CONTRACT ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
