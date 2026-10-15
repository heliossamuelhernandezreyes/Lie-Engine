extends SceneTree
const Packets=preload("res://lie_instance_packet_cache.gd")
const World=preload("res://lie_area_light_world.gd")
const Emitter=preload("res://lie_rect_emitter_3d.gd")
var checks: int=0
var failed: bool=false
var calls: int=0
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("PACKET FAIL ",label)
func entries() -> Array:
    calls+=1
    return [{"master":"test","pose":Transform3D(Basis.IDENTITY,Vector3(1,2,3)),"tint":[.5,.6,.7,0.]}]
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var cache=Packets.new();var catalog: Dictionary={"masters":{"test":{"levels":[{"start":0,"count":100},{"start":100,"count":10},{"start":110,"count":1}]}}}
    var a: Dictionary=cache.packet("master-v1".to_utf8_buffer(),entries,catalog,0,1000,10)
    check(a["ok"] and a["instances"].size()==96 and a["jobs"].to_int32_array()==PackedInt32Array([0,100,0,0]),"original instance/job ABI")
    check(a["instances"].decode_float(48)==1. and a["instances"].decode_float(52)==2. and a["instances"].decode_float(56)==3.,"authored transform preserved")
    var b: Dictionary=cache.packet("master-v1".to_utf8_buffer(),entries,catalog,0,1000,10)
    check(calls==1 and a["instances"]==b["instances"] and cache.reuses==1,"same immutable assembly avoids source call and repacking")
    cache.packet("master-v1".to_utf8_buffer(),entries,catalog,1,1000,10)
    cache.packet("master-v1".to_utf8_buffer(),entries,catalog,0,1000,10)
    check(calls==2 and cache.reuses==2,"independent LOD packets survive camera return")
    cache.packet("master-v2".to_utf8_buffer(),entries,catalog,0,1000,10);check(calls==3,"source identity change invalidates packets")
    cache.packet(PackedByteArray(),entries,catalog,0,1000,10);cache.packet(PackedByteArray(),entries,catalog,0,1000,10)
    check(calls==5,"unversioned dynamic adapters never reuse stale packets")
    var fallback: Dictionary=cache.packet(PackedByteArray(),entries,catalog,0,50,10)
    check(fallback["lod"]==1 and fallback["work"]==10,"same work budget and LOD fallback")
    check(not cache.packet(PackedByteArray(),entries,catalog,0,0,10)["ok"],"unrepresentable budget rejected")
    cache.packet("budget".to_utf8_buffer(),entries,catalog,0,1000,10)
    check(cache.packet("budget".to_utf8_buffer(),entries,catalog,0,50,10)["lod"]==1,"changed budget cannot reuse a previously accepted LOD")
    var world=World.new();root.add_child(world);var emitter=Emitter.new();emitter.light_id="key";world.add_child(emitter);check(world.refresh(),"world initialized")
    var emissions: Array=[];world.codes_changed.connect(func(snapshot: Dictionary):emissions.append(snapshot))
    var revision: int=world.registry.revision
    world.begin_update();world.begin_update();emitter.position=Vector3(1,2,3);world.refresh()
    check(emissions.is_empty() and world.registry.revision==revision,"batch never publishes intermediate source")
    world.end_update();check(emissions.is_empty(),"nested batch remains deferred")
    check(world.end_update() and emissions.size()==1 and world.render_snapshot()["lights"][0]["position"]==[1.,2.,3.],"final batch publishes one validated snapshot")
    check(not world.end_update(),"unmatched end is rejected")
    world.begin_update();world.refresh();world.end_update();check(emissions.size()==1,"unchanged batch emits no update")
    var other=Emitter.new();other.light_id="key";world.add_child(other);world.begin_update();emitter.position=Vector3(9,9,9)
    check(not world.end_update() and world.registry.revision==revision+1 and emissions.size()==1,"invalid final emitter set preserves accepted registry")
    world.queue_free();await process_frame;print("PACKETS/BATCH ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
