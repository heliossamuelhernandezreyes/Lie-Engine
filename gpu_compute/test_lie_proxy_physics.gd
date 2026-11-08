extends SceneTree
const Proxy=preload("res://lie_construction_proxy.gd")
const Hierarchy=preload("res://lie_construction_hierarchy.gd")
const Adapter=preload("res://lie_construction_field_adapter.gd")
const Field=preload("res://lie_field_quality_transport.gd")
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
    checks+=1
    if not value:failed=true;printerr("PROXY PHYSICS FAIL ",label)
func settle() -> void:
    for i in range(4):await physics_frame
    await process_frame
func read(path: String) -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("res://captures/hq_construction/"+path))
func run() -> void:
    var catalogs: Dictionary={}
    for bank in read("manifest.json").banks:catalogs[bank]=read("banks/"+bank+"/catalog.json")
    var world=Proxy.new();root.add_child(world);var cases: Array=[];var per_piece_fraction: float=0.
    for seed in [2102,7319]:
        var recipe: Dictionary=read("corner-"+str(seed)+".json");var c: Array=recipe.opening.center;var window:=Vector3(c[0],c[1],c[2])
        for grouped in [false,true]:
            var model: Dictionary=Proxy.build(recipe,recipe.instances,catalogs,grouped)
            check(not model.is_empty() and model.attachments.size()==781,"all source owners retained")
            check(model.body_count==(13 if grouped else 781) and model.rendered_proxy_triangles==0,"thirteen merged boxes or one box per piece; no drawn proxy")
            var owners: Dictionary={}
            for volume in model.volumes:
                for i in volume.members:owners[i]=true
            check(owners.size()==781,"volume groups retain every original attachment")
            check(world.configure(model),"native static bodies configured")
            await settle()
            check(world.get_child_count()==world.bodies.size(),"replaced bodies are released")
            var solid: Vector3=model.attachments[0].pose.origin;var dz:=Vector3(0,0,.4)
            check(not world.ray(solid+dz,solid-dz).is_empty(),"solid wall blocks actual engine ray")
            check(world.ray(window+dz,window-dz).is_empty(),"declared window passes actual engine ray")
            var hit: PackedFloat32Array=world.sphere_motion(solid+dz,solid-dz);var clear: PackedFloat32Array=world.sphere_motion(window+dz,window-dz)
            check(hit[0]<1. and clear[0]==1.,"native swept sphere stops at wall and crosses window")
            var a: Dictionary=Proxy.camera_sweep(solid+dz,solid-dz,model.volumes);var b: Dictionary=Proxy.camera_sweep(window+dz,window-dz,model.volumes)
            check(a.blocked and not b.blocked and not a.initial_overlap,"camera volume queries respect physical wall and opening")
            check(absf(a.fraction-hit[0])<.01,"axial camera sweep agrees with native sphere motion")
            if not grouped:per_piece_fraction=a.fraction
            else:check(absf(per_piece_fraction-a.fraction)*.8<.005,"separate details reduce wall contact overestimate below 5 mm")
            check(Proxy.camera_sweep(solid,solid+dz,model.volumes).initial_overlap,"camera overlap is explicit, never silently ignored")
            check(not world.get_children().any(func(n: Node):return n is MeshInstance3D),"physics contains no render mesh")
            cases.append({"seed":seed,"grouped":grouped,"metrics":world.metrics(),"wall_fraction":a.fraction,"native_wall_fraction":hit[0],"window_clear":true})
    var boxes: Array=[{"id":"wall","pose":Transform3D.IDENTITY,"size":Vector3(4,4,.1),"members":[0]}]
    world.configure({"volumes":boxes});await settle()
    var slide: Dictionary=Proxy.camera_move(Vector3(-.5,0,.4),Vector3(.5,0,-.4),boxes)
    check(slide.blocked and slide.slid and slide.position.x>.49 and slide.position.z>.074,"camera slides full lateral displacement without crossing wall")
    check(not world.sphere_overlaps(slide.position),"sliding endpoint clear in native physics")
    var recovery: Dictionary=Proxy.camera_move(Vector3.ZERO,Vector3(.2,0,0),boxes)
    check(recovery.initial_overlap and recovery.recovered and not recovery.recovery_failed and not Proxy.camera_overlaps(recovery.position,boxes),"initial overlap recovers before sliding")
    check(not world.sphere_overlaps(recovery.position),"recovered camera clear in native physics")
    var corner: Array=boxes.duplicate(true);corner.append({"id":"return","pose":Transform3D(Basis.IDENTITY,Vector3(1,0,1)),"size":Vector3(.1,4,2),"members":[1]})
    world.configure({"volumes":corner});await settle()
    var stop: Dictionary=Proxy.camera_move(Vector3(0,0,.4),Vector3(2,0,-.4),corner)
    check(stop.blocked and stop.position.x<.926 and stop.position.z>.074 and not world.sphere_overlaps(stop.position),"multiple contacts stop safely at inner corner")
    var seam: Dictionary=Proxy.camera_move(Vector3(1,0,0),Vector3(1,0,.2),corner)
    check(seam.recovered and not Proxy.camera_overlaps(seam.position,corner) and not world.sphere_overlaps(seam.position),"union-aware overlap recovery escapes intersecting boxes")
    check(Proxy.camera_move(Vector3(0,0,.4),Vector3(0,0,-4),boxes).position.z>.074,"large camera step cannot tunnel through wall")
    var tree: Dictionary=Hierarchy.build([{"id":"front/piece","bounds":AABB(Vector3(-.05,-.05,-1),Vector3(.1,.1,.1))},{"id":"front/offscreen","bounds":AABB(Vector3(10,0,-1),Vector3.ONE*.1)},{"id":"front/near","bounds":AABB(Vector3(-.01,-.01,-.01),Vector3.ONE*.02)}])
    check(tree.root.members.size()==3 and tree.walls==1 and tree.segments>=2,"hierarchy retains every leaf and wall/segment parents")
    var selection: Dictionary=Hierarchy.select(tree,Transform3D.IDENTITY,42.,1920)
    check(selection.mask==PackedByteArray([1,0,1]),"source crossing the near plane retained; only entirely offscreen leaf discarded")
    var away: Dictionary=Hierarchy.select(tree,Transform3D(Basis.IDENTITY,Vector3(100,100,0)),42.,1920)
    check(away.selected_jobs==0 and away.visited_nodes==1,"offscreen hierarchy rejected at root")
    var contain: Dictionary=Hierarchy.select(Hierarchy.build([{"id":"piece","bounds":AABB(Vector3(-.1,-.1,-1.1),Vector3(.2,.2,.2))}]),Transform3D.IDENTITY,42.,1920)
    check(contain.selected_jobs==1 and contain.visited_nodes==1 and contain.accepted_nodes==1,"fully contained hierarchy accepted at root")
    var roof: Dictionary=read("roof-2102.json");var materials: Dictionary=read("fields/materials.json").materials
    var field: Dictionary=Adapter.small_scene(roof.instances,materials);var transport=Field.new()
    check(not field.is_empty() and transport.bind_sources(field.model,field.sources) and transport.configure(field.model),"roof with unequal patch areas binds exact gather/outgoing field graphs")
    check(transport._count==148 and field.sources.factors.decode_u32(4)==field.sources.outgoing.decode_u32(4),"roof retains all field nodes and edge weights")
    transport.shutdown()
    var door: Dictionary=read("door-2102.json");var entries: Array=door.instances.duplicate(true)
    world.configure(Proxy.build(door,entries,catalogs,true));await settle()
    check(not world.ray(Vector3(0,1.025,.4),Vector3(0,1.025,-.4)).is_empty(),"closed independent leaf blocks doorway")
    for e in entries:
        if String(e.id).ends_with("/leaf"):
            var r:=Basis(Vector3.UP,deg_to_rad(75.));var p: Vector3=Vector3(e.origin[0],e.origin[1],e.origin[2])+Vector3(-.41,0,0)+r*Vector3(.41,0,0);e.origin=[p.x,p.y,p.z];e.basis_columns=[[r.x.x,r.x.y,r.x.z],[r.y.x,r.y.y,r.y.z],[r.z.x,r.z.y,r.z.z]]
    world.configure(Proxy.build(door,entries,catalogs,true));await settle()
    check(world.ray(Vector3(0,1.025,.4),Vector3(0,1.025,-.4)).is_empty(),"opened independent leaf exposes doorway")
    var file:=FileAccess.open("res://construction-proxy-physics.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"cases":cases,"physics_engine":ProjectSettings.get_setting("physics/3d/physics_engine","default"),"physical_android_tested":false},"  "));file.close()
    world.queue_free();await settle();print("PROXY PHYSICS ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
