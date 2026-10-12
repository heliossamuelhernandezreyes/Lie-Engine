extends "res://test_robot_gpu.gd"
const WorldLab=preload("res://lie_robot_world_lab.gd")
const Rig=preload("res://lie26_rig.gd")
func source_bank() -> String:return "res://captures/robot_world/library.bin"
func work_budget() -> int:return 1300000
func run() -> void:
    lab=WorldLab.new();root.add_child(lab);await settle();expect(lab.effect.capture_loaded and lab.effect.gpu_ready,"Actual combined Vulkan bank initialized")
    expect(meshes(lab)==0,"Physics triangles have no source mesh draw")
    var first: Dictionary=await read();verify(first)
    var pixels: PackedFloat32Array=first["color"];var size: int=first["output_size"];var floor_checked: int=0;var missing: int=0
    for y in range(0,size,12):
        for x in range(0,size,12):
            var uv: Vector2=(Vector2(x,y)+Vector2(.5,.5))/size;var tangent: float=tan(deg_to_rad(lab.camera.fov)*.5)
            var ray: Vector3=-lab.camera.basis.z+lab.camera.basis.x*((2*uv.x-1)*tangent)+lab.camera.basis.y*((1-2*uv.y)*tangent)
            if ray.y>=-.0001:continue
            var p: Vector3=lab.camera.position+ray*((-.02-lab.camera.position.y)/ray.y)
            if absf(p.x)>5.6 or absf(p.z)>5.6:continue
            floor_checked+=1
            if pixels[(y*size+x)*4+3]<.9:missing+=1
    expect(floor_checked>30 and missing==0,"Courtyard fine-LOD tiles have continuous interior coverage")
    expect(lab.command({"op":"set_values","values":{"view":"overview"}})["ok"],"Shared overview control")
    await settle();var overview: Dictionary=await read();verify(overview)
    # Collision triangles and rendered wall depth must occupy the same space.
    var depths: PackedFloat32Array=overview["depth"].to_byte_array().to_float32_array();var internal: int=overview["internal_size"];var wall_probes: int=0;var wall_matches: int=0;var max_wall_error: float=0;var boundary_probes: int=0;var boundary_misses: int=0
    for y in range(0,internal,32):
        for x in range(0,internal,32):
            var uv: Vector2=(Vector2(x,y)+Vector2(.5,.5))/internal;var tangent: float=tan(deg_to_rad(lab.camera.fov)*.5)
            var ray: Vector3=-lab.camera.basis.z+lab.camera.basis.x*((2*uv.x-1)*tangent)+lab.camera.basis.y*((1-2*uv.y)*tangent)
            var query:=PhysicsRayQueryParameters3D.create(lab.camera.position,lab.camera.position+ray*40,1,[lab.actor.get_rid()]);var hit: Dictionary=lab.get_world_3d().direct_space_state.intersect_ray(query)
            if hit.is_empty() or not str(hit["collider"].name).begins_with("house_"):continue
            wall_probes+=1;var wanted: float=(hit["position"]-lab.camera.position).dot(-lab.camera.basis.z);var actual: float=depths[y*internal+x]
            # A finite splat capture cannot promise exact single-pixel brick
            # silhouettes. Classify boundaries using independent physics rays,
            # never using the GPU error to decide which probes are interiors.
            var interior: bool=true
            for offset in [Vector2(-2,0),Vector2(2,0),Vector2(0,-2),Vector2(0,2)]:
                var neighbour: Vector2=uv+offset/internal;var r: Vector3=-lab.camera.basis.z+lab.camera.basis.x*((2*neighbour.x-1)*tangent)+lab.camera.basis.y*((1-2*neighbour.y)*tangent)
                var q:=PhysicsRayQueryParameters3D.create(lab.camera.position,lab.camera.position+r*40,1,[lab.actor.get_rid()]);var h: Dictionary=lab.get_world_3d().direct_space_state.intersect_ray(q)
                if h.is_empty() or h["collider"]!=hit["collider"] or h["normal"].dot(hit["normal"])<.99 or absf((h["position"]-hit["position"]).dot(hit["normal"]))>.003:interior=false;break
            if not interior:
                boundary_probes+=1
                if actual>wanted+.06:boundary_misses+=1
                continue
            expect(actual<=wanted+.06,"Rendered opaque architecture cannot fall behind its collision surface")
            if absf(actual-wanted)<.06:wall_matches+=1;max_wall_error=maxf(max_wall_error,absf(actual-wanted))
    expect(wall_matches>40,"Substantial exact-source wall/depth agreement")
    expect(lab.command({"op":"set_values","values":{"view":"third_person","move":[0,1]}})["ok"],"Native collision drive")
    var step: Dictionary=lab.command({"op":"advance","ticks":240});expect(step["ok"],"Physics advance accepted")
    for i in range(700):
        await physics_frame
        if lab.agent_snapshot()["motion"]["remaining_ticks"]==0:break
    await settle();verify(await read());expect(lab.state["motion"]["position"][2]<1,"Door crossing changes actual world position")
    expect(lab.command({"op":"set_values","values":{"roof":true,"view":"overview","unlit":true}})["ok"],"Roof and neutral-material inspection")
    await settle();verify(await read());expect(lab._metrics["instances"]<=192,"Combined instance ceiling")
    var report: Dictionary={"checks":checks,"failed":failed,"max_position_error_m":max_position_error,"max_geometric_normal_error":max_normal_error,"floor_checked_pixels":floor_checked,"floor_missing_pixels":missing,"wall_depth_probes":wall_probes,"wall_depth_matches":wall_matches,"boundary_probes":boundary_probes,"boundary_depth_misses":boundary_misses,"max_matching_wall_depth_error_m":max_wall_error,"device":first.get("device",""),"note":"Actual software Vulkan. Interior probes require physical plane agreement in a 2-pixel cross; boundary errors are retained separately. No physical GPU/Android FPS claim."}
    var file:=FileAccess.open("res://robot-world-gpu-verification.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close();print("R2 GPU ",JSON.stringify(report));root.remove_child(lab);lab.free();await process_frame;quit(1 if failed else 0)
