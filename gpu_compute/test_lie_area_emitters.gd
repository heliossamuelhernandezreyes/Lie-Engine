extends SceneTree
const Codes=preload("res://lie_area_emitter_codes.gd")
const World=preload("res://lie_area_light_world.gd")
const Rect=preload("res://lie_rect_emitter_3d.gd")
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
    checks+=1
    if not value:failed=true;printerr("AREA EMITTER FAIL ",label)
func run() -> void:
    var world=World.new();root.add_child(world)
    for id in ["key","fill"]:
        var e=Rect.new();e.light_id=id;e.area_enabled=true;e.position=Vector3(1,2,3);e.power_rgb_linear=Vector3(12,3,1);world.add_child(e)
    check(world.refresh(),"two panels fit atomically")
    var snapshot: Dictionary=world.render_snapshot()
    check(snapshot["lights"].size()==8 and snapshot["parent_ids"]==["key","key","key","key","fill","fill","fill","fill"],"stable logical and quadrature identities")
    var centroid:=Vector3.ZERO;var power:=Vector3.ZERO
    for i in range(4):
        var p: Array=snapshot["lights"][i]["position"];var rgb: Array=snapshot["lights"][i]["power_rgb"]
        centroid+=Vector3(p[0],p[1],p[2])*.25;power+=Vector3(rgb[0],rgb[1],rgb[2])
    check(centroid.is_equal_approx(Vector3(1,2,3)) and power.is_equal_approx(Vector3(12,3,1)),"centroid and total power preserved")
    var revision: int=world.registry.revision;var third=Rect.new();third.light_id="third";third.area_enabled=true;world.add_child(third)
    check(not world.refresh() and revision==world.registry.revision and world.render_snapshot()==snapshot,"capacity rejection preserves registry")
    world.remove_child(third);third.free()
    var key=world.get_child(0);key.size_m=Vector2(.8,.4);check(world.refresh() and world.render_snapshot()["lights"]!=snapshot["lights"],"size changes actual source positions")
    key.scale=Vector3(2,1,1);check(not world.refresh(),"scaled area rejected");key.scale=Vector3.ONE
    key.area_enabled=false;world.get_child(1).area_enabled=false;world.refresh();snapshot=world.render_snapshot()
    var zeros:=PackedByteArray();zeros.resize(128)
    check(snapshot["lights"]==world.registry.snapshot()["lights"] and snapshot["emission_descriptors"]==zeros,"legacy point codes exact")
    key.enabled=false;world.refresh();check(world.render_snapshot()["lights"][0]["power_rgb"]==[0.,0.,0.],"disabled logical source has no energy")
    for child in world.get_children():world.remove_child(child);child.free()
    check(world.refresh() and world.render_snapshot()["lights"].size()==1 and world.render_snapshot()["lights"][0]["power_rgb"]==[0.,0.,0.],"removing every emitter leaves one dark dummy channel")
    world.queue_free();await process_frame;print("AREA EMITTER ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
