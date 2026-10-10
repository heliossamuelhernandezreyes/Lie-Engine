extends SceneTree
const Doc=preload("res://workshop/lie_document.gd")
const Legacy=preload("res://lie15_model.gd")
var lab: Node3D
var effect: CompositorEffect
var checks: int=0
func _initialize() -> void: call_deferred("_run")
func _fail(message: String) -> void: push_error("LIE18 GPU FAIL: "+message); quit(1)
func _settle(count: int=4) -> void:
    for i in range(count): await process_frame
func _snapshot(item: CompositorEffect) -> Dictionary:
    item.call("request_readback")
    for i in range(180):
        await process_frame
        var result: Dictionary=item.call("readback")
        if not result.is_empty(): return result
    return {}
func _save(name: String) -> void:
    get_root().get_texture().get_image().save_png("res://lie18-"+name+".png")
func _meshes(node: Node) -> int:
    var count: int=1 if node is MeshInstance3D and (node as MeshInstance3D).is_visible_in_tree() else 0
    for child in node.get_children(): count+=_meshes(child)
    return count
func _find_button(node: Node,text: String) -> Button:
    if node is Button and (node as Button).text==text: return node
    for child in node.get_children():
        var found: Button=_find_button(child,text)
        if found!=null: return found
    return null
func _panels_fit(node: Node) -> bool:
    if node is PanelContainer:
        var bounds: Rect2=(node as PanelContainer).get_global_rect()
        if bounds.position.x<0 or bounds.end.x>get_root().size.x or bounds.end.y>get_root().size.y: return false
    for child in node.get_children():
        if not _panels_fit(child): return false
    return true
func _command(request: Dictionary) -> bool:
    var response: Dictionary=lab.call("command",request)
    checks+=1
    return bool(response.get("ok",false))

func _factors_reference(model: Dictionary,poses: Array[Transform3D]) -> PackedFloat32Array:
    var reference: Dictionary=model.duplicate(true)
    var patches: Array=model["patches"]; var count: int=patches.size()
    var visibility: Array=[]; visibility.resize(count*count); visibility.fill(0)
    for i in range(count):
        for j in range(i+1,count):
            var a: Vector3=Doc.vec(patches[i]["position"]); var b: Vector3=Doc.vec(patches[j]["position"])
            var na: Vector3=Doc.vec(patches[i]["normal"]); var nb: Vector3=Doc.vec(patches[j]["normal"])
            if na.dot(b-a)<=0 or nb.dot(a-b)<=0: continue
            var blocked: bool=false
            for pose in poses.slice(0,15):
                var inverse: Transform3D=pose.affine_inverse()
                if Legacy.Model.blocked(inverse*(a+na*.003),inverse*(b+nb*.003),[[[-.49999,-.49999,-.49999],[.49999,.49999,.49999]]]): blocked=true; break
            visibility[i*count+j]=0 if blocked else 1; visibility[j*count+i]=visibility[i*count+j]
    reference["mesh_visibility"]=visibility
    return Legacy.Model.factor_bytes(reference).to_float32_array()

func _run() -> void:
    lab=load("res://lie18_workshop.tscn").instantiate(); get_root().add_child(lab)
    lab.set_process(false); lab.set_physics_process(false)
    effect=lab.get("effect")
    if effect==null or not bool(effect.get("capture_loaded")): _fail("Prepared masters not loaded"); return
    for i in range(240):
        await process_frame
        if bool(effect.get("gpu_ready")) and int(effect.get("frame_count"))>4: break
    if not bool(effect.get("gpu_ready")) or _meshes(lab)!=0: _fail("Captured-only workshop not initialized"); return
    var snapshot: Dictionary=await _snapshot(effect)
    var lighting: CompositorEffect=lab.get("lighting")
    var transport: Dictionary=await _snapshot(lighting)
    if snapshot.is_empty() or transport.is_empty(): _fail("GPU readback missing"); return
    var source: Dictionary=lab.get("model")
    var poses: Array[Transform3D]=[]; poses.assign(source["poses"])
    var expected: PackedFloat32Array=_factors_reference(source,poses)
    var actual: PackedFloat32Array=transport["form_factors"]
    var error: float=0; var reciprocity: float=0; var row_max: float=0
    var n: int=source["patches"].size()
    for i in range(n):
        var sum: float=0
        for j in range(n):
            var value: float=actual[i*n+j]
            if not is_finite(value) or value<0: _fail("Nonfinite/negative transfer"); return
            error=maxf(error,absf(value-expected[i*n+j])); sum+=value
            reciprocity=maxf(reciprocity,absf(float(source["patches"][i]["area"])*value-float(source["patches"][j]["area"])*actual[j*n+i]))
        row_max=maxf(row_max,sum)
    if error>.00005 or reciprocity>.00001 or row_max>1.00001: _fail("GPU factors vs independent CPU visibility/energy oracle: "+str([error,reciprocity,row_max])); return
    var graphs_before: int=int(lighting.get("graph_rebuilds")); await _settle(8)
    if int(lighting.get("graph_rebuilds"))!=graphs_before: _fail("Idle scene repeatedly rebuilds transport"); return
    if not _panels_fit(lab.get("ui")): _fail("Workshop panels extend outside the window"); return
    _save("workshop")
    var document: RefCounted=lab.get("document")
    var fingerprint: Dictionary={}
    for name in effect.get("masters"): fingerprint[name]=effect.get("masters")[name]["sample_sha256"]
    # Exercise an actual visible UI signal, then the identical public command API.
    lab.set("selected","head"); lab.call("_refresh_ui")
    var button: Button=_find_button(lab.get("ui"),"Duplicar")
    if button==null: _fail("User control missing"); return
    button.pressed.emit(); await _settle()
    if document.get("state")["pieces"].size()!=16: _fail("User duplicate control failed"); return
    _save("duplicated")
    if not _command({"op":"undo"}): _fail("Agent undo failed"); return
    # Editing later poses through the user controls must retain earlier keys.
    if not _command({"op":"set_time","value":0}): _fail("Key time"); return
    lab.set("selected","head"); lab.call("_refresh_ui"); lab.call("_set_angle",12.0); lab.call("_record_key")
    if not _command({"op":"set_time","value":1}): _fail("Later key time"); return
    lab.call("_set_angle",-18.0); lab.call("_record_key")
    if document.get("state")["tracks"]["head"]!=[[0.0,12.0],[1.0,-18.0]]: _fail("User pose editor lost earlier animation keys"); return
    if not _command({"op":"batch","commands":[{"op":"set_track","id":"head","keys":[]},{"op":"update_piece","id":"head","values":{"angle_deg":0}},{"op":"set_time","value":0}]}): _fail("Restore pose"); return
    await _settle(5)
    var box_frame: Dictionary=await _snapshot(effect)
    if not _command({"op":"update_piece","id":"head","values":{"master":"cylinder"}}): _fail("Switch master"); return
    await _settle(5)
    var cylinder_frame: Dictionary=await _snapshot(effect)
    if cylinder_frame["raw_color"]==box_frame["raw_color"]: _fail("Master switch did not alter captured geometry"); return
    if not _command({"op":"undo"}): _fail("Restore master"); return
    var cylinder_button: Button=_find_button(lab.get("ui"),"Cilindro")
    if cylinder_button==null: _fail("Cylinder library control missing"); return
    cylinder_button.pressed.emit(); await _settle(5)
    if document.get("state")["pieces"].size()!=16 or document.get("state")["pieces"][-1]["master"]!="cylinder": _fail("Cylinder library control failed"); return
    _save("assembly")
    if not _command({"op":"undo"}): _fail("Undo cylinder"); return
    # External file transport operates on the running editor, not a detached UI.
    var inbox:=FileAccess.open("user://workshop/inbox.json",FileAccess.WRITE)
    inbox.store_string(JSON.stringify({"op":"set_camera","expected_revision":document.get("revision"),"values":{"yaw_deg":45}})); inbox.close()
    lab.call("_poll_agent")
    var outbox: Variant=JSON.parse_string(FileAccess.get_file_as_string("user://workshop/outbox.json"))
    if not outbox is Dictionary or not outbox["result"]["ok"] or float(document.get("state")["camera"]["yaw_deg"])!=45: _fail("Running-editor agent inbox/outbox failed"); return
    if not _command({"op":"set_light","index":0,"values":{"position":[1.7,2.1,1.8]}}): _fail("Light command"); return
    await _settle(5); _save("light")
    var after_light: Dictionary=await _snapshot(effect)
    if after_light["raw_color"]==snapshot["raw_color"]: _fail("Moving light did not change captured shading"); return
    var medium_reports: Dictionary={}
    for fluid in ["water","rain"]:
        if not _command({"op":"set_settings","values":{"fluid":fluid}}): _fail("Optical command"); return
        lab.set("_fluid_time",.3); lab.call("_update_optics"); await _settle(5)
        var optical: CompositorEffect=lab.get("optics")
        var optical_data: Dictionary=await _snapshot(optical)
        if optical_data.is_empty(): _fail("Optical layers not integrated"); return
        var coefficients: PackedFloat32Array=optical_data["coefficients"]
        var covered: int=0
        var misplaced: int=0
        for pixel in range(coefficients.size()/4):
            if coefficients[pixel*4]>=0:
                covered+=1
                for c in range(4):
                    if not is_finite(coefficients[pixel*4+c]) or coefficients[pixel*4+c]<0 or coefficients[pixel*4+c]>1.00001: _fail("Optical coefficients outside bounds"); return
                if fluid=="water":
                    # Independent Camera3D projection checks that every covered
                    # optical pixel intersects the finite horizontal water tile.
                    var camera: Camera3D=lab.get("camera")
                    var screen:=Vector2((float(pixel%256)+.5)*get_root().size.x/256,(float(pixel/256)+.5)*get_root().size.y/256)
                    var origin: Vector3=camera.project_ray_origin(screen)
                    var ray: Vector3=camera.project_ray_normal(screen)
                    var t: float=(-1.02-origin.y)/ray.y if absf(ray.y)>1e-8 else -1
                    var hit: Vector3=origin+ray*t
                    if t<=0 or absf(hit.x)>1.68 or absf(hit.z-.5)>1.13: misplaced+=1
        if covered==0: _fail("No visible "+fluid+" samples"); return
        if misplaced>0: _fail("Optical projection disagrees with physical camera rays: "+str(misplaced)); return
        medium_reports[fluid]={"covered_pixels":covered,"misplaced_pixels":misplaced,"optical_resolution":256,"layers_max":4}
        _save(fluid)
    if not _command({"op":"set_settings","values":{"fluid":"off"}}): _fail("Disable optics"); return
    (lab.get("ui") as CanvasLayer).visible=false
    for frame in range(32):
        if not _command({"op":"batch","commands":[{"op":"set_time","value":float(frame)/16},{"op":"set_camera","values":{"yaw_deg":10+float(frame)*2}}]}): _fail("Animation command"); return
        await _settle(3); _save("motion-%02d" % frame)
    await _settle(8)
    var final: Dictionary=await _snapshot(effect)
    if int(final["asset_uploads"])!=1 or _meshes(lab)!=0 or int(final["counters"][8])<=0: _fail("Master reuse / temporal history invariant"); return
    for name in fingerprint:
        if fingerprint[name]!=effect.get("masters")[name]["sample_sha256"]: _fail("Animation recaptured or changed master"); return
    var report: Dictionary={"experiment":"LIE18-workshop-agent-api-v1","device":final["device"],"hardware_fps_claim":false,
        "visible_source_meshes":0,"immutable_combined_master_uploads":final["asset_uploads"],"capture_packages":fingerprint,
        "user_duplicate_button_verified":true,"user_cylinder_button_verified":true,"user_animation_keys_preserved":true,"workshop_panels_fit_window":true,"master_switch_verified":true,"live_agent_inbox_outbox_verified":true,"atomic_agent_commands":checks,
        "gpu_factor_maximum_cpu_oracle_error":error,"gpu_factor_maximum_area_reciprocity_error":reciprocity,"gpu_factor_maximum_row_sum":row_max,
        "idle_transport_rebuilds":0,"rigid_motion_frames":32,"temporal_accepted_pixels":final["counters"][8],"consumer_bytes":final["allocation_bytes"],
        "optical_media":medium_reports,"snapshot":lab.call("agent_snapshot"),
        "known_limits":["Conservative OBB collision/shadow proxies, including cylinders","Joint hierarchy is kinematic; no balance or inverse kinematics solver","Water uses prescribed normal waves; rain uses ballistic drop sprites","Four optical layers; no off-screen refraction or fluid volume solver","Measured renderer is software Vulkan, not Android FPS","First workshop ships two capture masters; Blender remains external"]}
    var file:=FileAccess.open("res://lie18-diagnostic.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"  ",true,true))
    print("LIE18 GPU PASS ",JSON.stringify(report))
    lab.queue_free(); await _settle(3); quit(0)
