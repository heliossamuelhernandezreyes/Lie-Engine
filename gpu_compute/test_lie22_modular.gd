extends SceneTree
const Doc=preload("res://workshop/lie_modular_document.gd")
var lab: Node3D
var effect: CompositorEffect
var checks: int=0
var failed: bool=false
var results: Dictionary={}
func _initialize() -> void:call_deferred("_run")
func expect(ok: bool,message: String) -> bool:
    checks+=1
    if not ok:failed=true;push_error("LIE22 GPU FAIL: "+message)
    return ok
func _settle(count: int=3) -> void:
    for i in range(count):await process_frame
func _read() -> Dictionary:
    effect.call("request_readback")
    for i in range(180):
        await process_frame
        var data: Dictionary=effect.call("readback")
        if not data.is_empty():return data
    return {}
func _command(request: Dictionary) -> bool:return expect(lab.call("command",request).get("ok",false),"Command "+str(request.get("op")))
func _screen(name: String) -> void:get_root().get_texture().get_image().save_png("res://lie22-"+name+"-workshop.png")
func _image(data: Dictionary,name: String) -> void:
    var image:=Image.create_from_data(data["output_size"],data["output_size"],false,Image.FORMAT_RGBAF,data["color"].to_byte_array());image.convert(Image.FORMAT_RGBA8);image.save_png("res://lie22-"+name+".png")
func _meshes(node: Node) -> int:
    var count: int=1 if node is MeshInstance3D and node.is_visible_in_tree() else 0
    for child in node.get_children():count+=_meshes(child)
    return count
func _button(node: Node,text: String) -> Button:
    if node is Button and node.text==text:return node
    for child in node.get_children():
        var found: Button=_button(child,text)
        if found!=null:return found
    return null
func _panels_fit(node: Node) -> bool:
    if node is PanelContainer:
        var r: Rect2=node.get_global_rect()
        if r.position.x<0 or r.end.x>1280 or r.end.y>800:return false
    for child in node.get_children():
        if not _panels_fit(child):return false
    return true
func _ring(data: Dictionary) -> Vector3:
    var size: int=data["output_size"];var sum:=Vector3.ZERO;var count: int=0;var pixels: PackedFloat32Array=data["color"]
    for y in range(size/2-60,size/2+61):
        for x in range(size/2-60,size/2+61):
            var radius: float=Vector2(x-size/2,y-size/2).length()
            if radius<44 or radius>58:continue
            var i: int=(y*size+x)*4;sum+=Vector3(pixels[i],pixels[i+1],pixels[i+2]);count+=1
    return sum/maxi(count,1)
func _dark(data: Dictionary) -> int:
    var size: int=data["output_size"];var count: int=0;var pixels: PackedFloat32Array=data["color"]
    for y in range(size/2-40,size/2+41):
        for x in range(size/2-40,size/2+41):
            var i: int=(y*size+x)*4
            if maxf(pixels[i],maxf(pixels[i+1],pixels[i+2]))<.16:count+=1
    return count
func _compare(a: Dictionary,b: Dictionary) -> Dictionary:
    var x: PackedFloat32Array=a["color"];var y: PackedFloat32Array=b["color"];var union: int=0;var intersection: int=0;var difference: float=0
    for i in range(0,x.size(),4):
        var aa: bool=x[i+3]>.5;var bb: bool=y[i+3]>.5
        if aa or bb:union+=1
        if aa and bb:
            intersection+=1
            for c in range(3):difference+=absf(x[i+c]-y[i+c])
    return {"iou":float(intersection)/maxi(union,1),"rgb_mae":difference/maxi(intersection*3,1)}
func _depth(data: Dictionary,point: Vector3) -> float:
    var camera: Camera3D=lab.get("camera");var d: Vector3=point-camera.position;var z: float=d.dot(-camera.basis.z);var tangent: float=tan(deg_to_rad(camera.fov)*.5)
    var size: int=data["internal_size"];var x: int=int((d.dot(camera.basis.x)/(z*tangent)+1)*.5*size);var y: int=int((1-d.dot(camera.basis.y)/(z*tangent))*.5*size)
    var depth: PackedFloat32Array=data["depth"].to_byte_array().to_float32_array();return depth[clampi(y,0,size-1)*size+clampi(x,0,size-1)]
func _run() -> void:
    lab=load("res://lie22_modular_lab.tscn").instantiate();get_root().add_child(lab);effect=lab.get("effect")
    if not expect(effect!=null and effect.get("capture_loaded"),"Shared neutral library loaded"):quit(1);return
    _command({"op":"set_values","values":{"camera_elevation":0}})
    for i in range(240):
        await process_frame
        if effect.get("gpu_ready") and int(effect.get("frame_count"))>=1:break
    if not expect(effect.get("gpu_ready") and _meshes(lab)==0,"Actual Vulkan captured-only renderer"):quit(1);return
    var original: Dictionary=await _read()
    if not expect(not original.is_empty(),"Actual GPU readback"):quit(1);return
    var covered: int=0
    for i in range(3,original["color"].size(),4):
        if original["color"][i]>.5:covered+=1
    expect(covered>20000,"Eye covers real pixels")
    expect(_panels_fit(lab.get("ui")),"Eye controls fit window")
    _image(original,"eye-blue");_screen("eye-blue")
    var blue: Vector3=_ring(original);expect(blue.z>blue.x*1.3,"Blue iris receives its material color")
    var brown_button: Button=_button(lab.get("ui"),"Marrón")
    if not expect(brown_button!=null,"Actual user iris preset"):quit(1);return
    brown_button.pressed.emit();await _settle();var brown: Dictionary=await _read();_image(brown,"eye-brown")
    var b: Vector3=_ring(brown);expect(b.x>b.z*1.3 and brown["color"]!=original["color"],"User preset changes captured fibers")
    _command({"op":"set_values","values":{"iris_color":[.37,.62,.28],"pupil_radius":.0008}});await _settle();var small: Dictionary=await _read();_image(small,"eye-small")
    _command({"op":"set_values","values":{"pupil_radius":.0032}});await _settle();var large: Dictionary=await _read();_image(large,"eye-large")
    results["small_pupil_dark_pixels"]=_dark(small);results["large_pupil_dark_pixels"]=_dark(large)
    expect(_dark(large)>maxi(_dark(small)*2,100),"Pupil changes geometry rather than recoloring iris")
    _command({"op":"set_values","values":{"pupil_radius":.0017,"gaze_yaw":25,"gaze_pitch":-12}});await _settle();var gaze: Dictionary=await _read();_image(gaze,"eye-gaze");_screen("eye-gaze")
    expect(gaze["color"]!=large["color"],"Invisible eye articulation changes view")
    _command({"op":"set_values","values":{"gaze_yaw":0,"gaze_pitch":0,"light_azimuth":40}});await _settle();var lit: Dictionary=await _read();_image(lit,"eye-light")
    expect(lit["color"]!=gaze["color"],"Live light changes eye shading")
    var frame_count: int=effect.get("frame_count");await _settle(6);expect(int(effect.get("frame_count"))==frame_count,"Static eye reuses GPU image")
    var pending: Dictionary=effect.get("_pending")
    expect(not effect.call("configure",pending["parameters"],pending["instances"],PackedByteArray(),1),"Renderer rejects empty jobs")
    expect(not effect.call("configure",pending["parameters"],pending["instances"],pending["jobs"],750001),"Renderer rejects excess work")
    var before: Dictionary=lab.get("document").snapshot()
    expect(not lab.call("command",{"op":"set_values","values":{"pupil_radius":NAN}}).get("ok",false) and lab.get("document").snapshot()==before,"UI and agents share atomic nonfinite guard")
    # Correlated file transport edits the already running user interface.
    var inbox:=FileAccess.open("user://modular22/inbox.json",FileAccess.WRITE)
    inbox.store_string(JSON.stringify({"request_id":"lie22-live-test","request":{"op":"set_values","expected_revision":lab.get("document").revision,"values":{"iris_color":[.22,.57,.76]}}}));inbox.close();lab.call("_poll_agent")
    var response: Variant=JSON.parse_string(FileAccess.get_file_as_string("user://modular22/outbox.json"))
    expect(response is Dictionary and response.get("request_id")=="lie22-live-test" and response["result"]["ok"],"Live correlated agent request")
    # The same immutable library stays resident when switching to construction.
    _command({"op":"set_values","values":{"mode":"wall","coating":false,"simulate":false,"camera_yaw":0,"camera_elevation":15,"light_azimuth":-35}});await _settle();var grouped: Dictionary=await _read()
    _image(grouped,"wall-grouped");_screen("wall-grouped")
    expect(lab.call("agent_snapshot")["metrics"]["grouped_modules"]==12 and grouped["instances"]==13,"48 bricks represented by 12 modules plus floor")
    expect(_panels_fit(lab.get("ui")),"Wall controls fit window")
    _command({"op":"set_values","values":{"grouped":false}});await _settle();var expanded: Dictionary=await _read();_image(expanded,"wall-expanded")
    expect(expanded["instances"]==61,"Expanded mode uses 48 shared bricks, 12 mortar pieces and floor")
    var comparison: Dictionary=_compare(grouped,expanded);results["grouped_vs_expanded"]=comparison
    expect(comparison["iou"]>.95,"Grouping preserves depth silhouette")
    _command({"op":"set_values","values":{"grouped":true,"coating":true}});await _settle();var coated: Dictionary=await _read();_image(coated,"wall-coated");_screen("wall-coated")
    expect(coated["color"]!=grouped["color"],"Concrete coating occludes masonry")
    _command({"op":"set_values","values":{"coating":false,"seed":1204}});await _settle();var variation: Dictionary=await _read()
    expect(variation["color"]!=grouped["color"],"Seed changes per-brick material without new captures")
    _command({"op":"set_values","values":{"seed":1203,"coating":true,"simulate":true}});await _settle();var wall_before: Dictionary=await _read()
    var target: Vector3=lab.call("cell_center",27)+Vector3(0,0,.055);var before_depth: float=_depth(wall_before,target)
    var hit_button: Button=_button(lab.get("ui"),"Golpear")
    if not expect(hit_button!=null,"User destruction control"):quit(1);return
    hit_button.pressed.emit();await _settle()
    var snapshot: Dictionary=lab.call("agent_snapshot")
    expect(snapshot["metrics"]["removed_bricks"]==1 and snapshot["metrics"]["grouped_modules"]==11 and snapshot["metrics"]["dynamic_bodies"]==4,"Local damage wakes only one module and four cut pieces")
    var first_bodies: Dictionary=lab.get("_bodies").duplicate()
    var initial_positions: Dictionary={}
    for name in first_bodies:initial_positions[name]=first_bodies[name]["body"].position
    var sequence: Array=[]
    for step in range(12):
        await _settle(2);var data: Dictionary=await _read();_image(data,"wall-step-%03d"%step);sequence.append({"step":step,"time_us":Time.get_ticks_usec(),"frames":data["frames"]})
    var moved: bool=false
    for name in first_bodies:
        var body: RigidBody3D=first_bodies[name]["body"]
        if body.position.distance_to(initial_positions[name])>.01:moved=true
        expect(body.position.is_finite() and body.linear_velocity.is_finite(),"Finite native rigid-body fragment")
    expect(moved,"Native physics moves fragments with gravity and collisions")
    _command({"op":"set_values","values":{"simulate":false}});await _settle();var damaged: Dictionary=await _read();_image(damaged,"wall-damaged");_screen("wall-damaged")
    results["hole_depth_before_m"]=before_depth;results["hole_depth_after_m"]=_depth(damaged,target)
    expect(_depth(damaged,target)>before_depth+.025,"Removed brick opens a depth-correct hole")
    _command({"op":"strike","cell":28});await _settle()
    var kept: bool=true
    for name in first_bodies:
        if not lab.get("_bodies").has(name) or lab.get("_bodies")[name]["body"]!=first_bodies[name]["body"]:kept=false
    expect(kept,"Second impact preserves existing fragment bodies")
    _command({"op":"undo"});await _settle();expect(lab.get("_bodies").size()==4,"Undo removes newly created fragments")
    var wall_frames: int=effect.get("frame_count");await _settle(6);expect(int(effect.get("frame_count"))==wall_frames,"Frozen wall reuses completed GPU image")
    _command({"op":"reset_wall"});await _settle();expect(lab.get("_bodies").is_empty() and lab.call("agent_snapshot")["metrics"]["grouped_modules"]==12,"Restored wall regrouped")
    # Support connectivity, not engineering stress: removing all foundation
    # cells activates the disconnected upper bricks as native rigid bodies.
    var commands: Array=[]
    for col in range(6):commands.append({"op":"strike","cell":col})
    _command({"op":"batch","commands":commands});await _settle();var collapse: Dictionary=await _read();_image(collapse,"wall-detached")
    var detached: Dictionary=lab.call("agent_snapshot")
    expect(detached["metrics"]["unsupported_bricks"]==42 and detached["metrics"]["dynamic_bodies"]==66,"Disconnected support activates upper wall within explicit budgets")
    expect(collapse["instances"]<=128 and collapse["sample_invocations"]<=750000,"Collapse respects renderer bounds")
    _command({"op":"set_values","values":{"simulate":true}})
    for i in range(6):await _settle(2)
    _command({"op":"set_values","values":{"simulate":false}});await _settle();var fallen: Dictionary=await _read();_image(fallen,"wall-collapsed");_screen("wall-collapsed")
    _command({"op":"reset_wall"});await _settle();var final: Dictionary=await _read()
    expect(final["asset_uploads"]==1,"All poses, materials and destruction share one immutable library upload")
    expect(_meshes(lab)==0,"Source meshes remain invisible after collapse")
    results.merge({"checks":checks,"failed":failed,"device":final["device"],"allocation_bytes":final["allocation_bytes"],"library_bytes":final["library_bytes"],"asset_uploads":final["asset_uploads"],"grouped_instances":grouped["instances"],"expanded_instances":expanded["instances"],"grouped_sample_invocations":grouped["sample_invocations"],"expanded_sample_invocations":expanded["sample_invocations"],"profile":final["profile"],"sequence":sequence,"output_size":final["output_size"],"internal_size":final["internal_size"],"original_mesh_drawn":false,"android_measured":false})
    var report:=FileAccess.open("res://lie22-diagnostic.json",FileAccess.WRITE);report.store_string(JSON.stringify(results,"  ",true,true));report.close()
    print("LIE22 GPU ","FAIL" if failed else "PASS"," ",checks," checks ",JSON.stringify(results));lab.queue_free();await _settle(2);quit(1 if failed else 0)
