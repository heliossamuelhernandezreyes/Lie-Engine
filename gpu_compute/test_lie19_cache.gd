extends SceneTree
## Exercise cached transport against deliberate fresh recomputation, and an
## actual external Python client against the open workshop, in software Vulkan.
var lab: Node3D
var lighting: CompositorEffect
var effect: CompositorEffect
var checks: int=0
func _initialize() -> void: call_deferred("_run")
func _fail(message: String) -> void: push_error("LIE19 GPU FAIL: "+message); quit(1)
func _settle(count: int=3) -> void:
    for i in range(count): await process_frame
func _read(item: CompositorEffect) -> Dictionary:
    item.call("request_readback")
    for i in range(180):
        await process_frame
        var data: Dictionary=item.call("readback")
        if not data.is_empty(): return data
    return {}
func _command(request: Dictionary) -> bool:
    checks+=1
    return bool(lab.call("command",request).get("ok",false))
func _maximum_error(a: PackedFloat32Array,b: PackedFloat32Array) -> float:
    if a.size()!=b.size(): return INF
    var error: float=0
    for i in range(a.size()):
        if not is_finite(a[i]) or not is_finite(b[i]): return INF
        error=maxf(error,absf(a[i]-b[i]))
    return error
func _client(request: Dictionary,name: String) -> Dictionary:
    var output: String="res://lie19-client-"+name+".json"
    if FileAccess.file_exists(output): DirAccess.remove_absolute(output)
    var snapshot: Dictionary=lab.call("agent_snapshot")
    var executable: String=ProjectSettings.globalize_path("res://../tools/lie_workshop_client.py")
    var pid: int=OS.create_process("python3",[executable,"--directory",snapshot["inbox"].get_base_dir(),"--command",JSON.stringify(request),"--timeout","30","--output",ProjectSettings.globalize_path(output)])
    if pid<=0: return {}
    var deadline: int=Time.get_ticks_msec()+35000
    while Time.get_ticks_msec()<deadline:
        await process_frame
        lab.call("_poll_agent")
        if FileAccess.file_exists(output):
            var response: Variant=JSON.parse_string(FileAccess.get_file_as_string(output))
            if response is Dictionary: return response
    if OS.is_process_running(pid): OS.kill(pid)
    return {}
func _summary(rows: Array,key: String) -> Dictionary:
    var values: Array=rows.map(func(row: Dictionary): return float(row[key])/1000000)
    values.sort()
    return {"samples":values.size(),"median_ms":values[int(values.size()/2)],"p95_ms":values[mini(values.size()-1,int(ceil(values.size()*.95))-1)]} if not values.is_empty() else {}

func _run() -> void:
    lab=load("res://lie18_workshop.tscn").instantiate(); get_root().add_child(lab)
    lab.set_process(false); lab.set_physics_process(false)
    lighting=lab.get("lighting"); effect=lab.get("effect")
    if lighting==null: _fail("Prepared capture masters missing"); return
    for i in range(240):
        await process_frame
        if effect.get("gpu_ready"): break
    if not effect.get("gpu_ready"): _fail("Renderer did not initialize"); return
    if not _command({"op":"runtime_profile","enabled":true}): _fail("Runtime profiler command"); return
    var doc: RefCounted=lab.get("document")
    var revision: int=doc.get("revision")
    if revision!=0 or not (lab.get("profile_control") as CheckBox).button_pressed: _fail("Profiler changed authored document / UI does not share agent control"); return
    if not _command({"op":"save_document"}): _fail("Save initial showcase"); return
    var scenarios: Array=[
        ["lamp_position",{"op":"set_light","index":0,"values":{"position":[1.7,2.1,1.8]}},false],
        ["lamp_color",{"op":"set_light","index":0,"values":{"power_rgb":[45,110,145]}},false],
        ["tint",{"op":"set_material","name":"paint","values":{"tint_linear":[.12,.4,.75]}},false],
        ["absorption",{"op":"set_material","name":"paint","values":{"absorption_code":770}},false],
        ["metal",{"op":"set_material","name":"steel","values":{"metallic":.3}},false],
        ["roughness",{"op":"set_material","name":"steel","values":{"roughness":.6}},false],
        ["bounces",{"op":"set_settings","values":{"bounces":3}},false],
        ["water",{"op":"set_settings","values":{"fluid":"water"}},false],
        ["water_off",{"op":"set_settings","values":{"fluid":"off"}},false],
        ["resize",{"op":"update_piece","id":"head","values":{"scale":[.7,.42,.46]}},true],
        ["rotate",{"op":"update_piece","id":"head","values":{"angle_deg":23}},true],
        ["animate",{"op":"set_time","value":.5},true],
        ["duplicate",{"op":"duplicate_piece","id":"helmet","source":"head"},true]
    ]
    var comparisons: Array=[]
    var max_error: float=0
    for scenario in scenarios:
        var before: Dictionary=lighting.call("metrics")
        if not _command(scenario[1]): _fail("Command "+scenario[0]); return
        await _settle()
        var cached: Dictionary=await _read(lighting)
        var delta: int=int(cached["graph_rebuilds"])-int(before["graph_rebuilds"])
        if delta!=(1 if scenario[2] else 0): _fail("Wrong graph invalidation: "+scenario[0]+" delta "+str(delta)); return
        var last: Dictionary=cached["metrics"]["last_solve"]
        lighting.set("diagnostic_force_graph",true); lighting.call("configure_workshop",lab.get("model"))
        await _settle()
        var fresh: Dictionary=await _read(lighting)
        lighting.set("diagnostic_force_graph",false)
        var factor_error: float=_maximum_error(cached["form_factors"],fresh["form_factors"])
        var energy_error: float=_maximum_error(cached["irradiance"],fresh["irradiance"])
        max_error=maxf(max_error,maxf(factor_error,energy_error))
        if factor_error>.000001 or energy_error>.000001: _fail("Cached output differs from full recomputation: "+scenario[0]); return
        comparisons.append({"change":scenario[0],"graph_rebuilt":scenario[2],"factor_error":factor_error,"irradiance_error":energy_error,"upload_bytes":last["upload_bytes"],"dispatches":last["dispatches"]})
    # Two pending edits can replace a packet before rendering. Final geometry
    # must still be compared with the last consumed state, never the last call.
    if not _command({"op":"update_piece","id":"head","values":{"angle_deg":-21}}) or not _command({"op":"set_material","name":"paint","values":{"roughness":.23}}): _fail("Coalesced edits"); return
    await _settle()
    var coalesced: Dictionary=await _read(lighting)
    lighting.set("diagnostic_force_graph",true); lighting.call("configure_workshop",lab.get("model")); await _settle()
    var coalesced_fresh: Dictionary=await _read(lighting)
    lighting.set("diagnostic_force_graph",false)
    if _maximum_error(coalesced["irradiance"],coalesced_fresh["irradiance"])>.000001: _fail("Coalesced packet used a stale graph"); return
    # Interleaved pairs limit thermal/order drift. Each identical light edit
    # runs with cache and with deliberate reconstruction of the same graph.
    var benchmark_start: int=int(lighting.get("frame_count"))
    for i in range(12):
        for forced in ([false,true] if i%2==0 else [true,false]):
            lighting.set("diagnostic_force_graph",forced)
            if not _command({"op":"set_light","index":0,"values":{"power_rgb":[80+i*2,105,140]}}): _fail("Benchmark light"); return
            # Force delivery even when the second command has identical values.
            lighting.call("configure_workshop",lab.get("model")); await _settle(2)
    lighting.set("diagnostic_force_graph",false); await _settle(6)
    var measured: Dictionary=lighting.call("metrics")
    var rows: Array=measured["profile"].filter(func(row: Dictionary): return int(row["serial"])>benchmark_start)
    var reused: Array=rows.filter(func(row: Dictionary): return not row["graph_rebuilt"])
    var forced: Array=rows.filter(func(row: Dictionary): return row["graph_rebuilt"])
    if reused.size()<10 or forced.size()<10: _fail("Missing actual Vulkan timing pairs: "+str([reused.size(),forced.size()])); return
    var solves_before: int=int(lighting.get("frame_count")); await _settle(6)
    if int(lighting.get("frame_count"))!=solves_before: _fail("Idle scene still dispatches lighting"); return
    var external: Dictionary=await _client({"op":"snapshot"},"snapshot")
    if external.is_empty() or not external["result"]["ok"] or not external["request_id"] is String: _fail("External client / correlated snapshot"); return
    revision=int(external["snapshot"]["revision"])
    var edited: Dictionary=await _client({"op":"set_camera","expected_revision":revision,"values":{"yaw_deg":35}},"edit")
    if edited.is_empty() or not edited["result"]["ok"] or doc.get("state")["camera"]["yaw_deg"]!=35: _fail("External client did not update the running scene"); return
    var rejected: Dictionary=await _client({"op":"set_camera","expected_revision":revision,"values":{"yaw_deg":-90}},"conflict")
    if rejected.is_empty() or rejected["result"].get("error")!="revision_conflict" or doc.get("state")["camera"]["yaw_deg"]!=35: _fail("External stale-revision command was applied"); return
    # Restore a clear showcase while keeping this run's measured counters.
    if not _command({"op":"load_document"}): _fail("Restore saved workshop"); return
    await _settle(8); lab.call("_process",1.1)
    get_root().get_texture().get_image().save_png("res://lie19-workshop.png")
    var rendered: Dictionary=await _read(effect)
    var report: Dictionary={"experiment":"LIE19-transport-cache-v1","device":rendered["device"],"hardware_fps_claim":false,"equivalence_cases":comparisons,"maximum_cached_vs_fresh_error":max_error,"coalesced_edits_verified":true,"idle_lighting_solves":0,"external_python_client_verified":true,"external_revision_conflict_verified":true,"runtime_profiler_shared_with_ui":true,"atomic_commands":checks,"matched_timing_pairs":{"cached":_summary(reused,"transport_gpu_ns"),"forced_rebuild":_summary(forced,"transport_gpu_ns"),"raw_vulkan_nanoseconds":rows},"consumer_gpu":_summary(rendered["profile"],"consumer_gpu_ns"),"metrics":lab.call("runtime_metrics"),"note":"Software Vulkan; Lie pass timings are not total frame time or Android performance."}
    var file:=FileAccess.open("res://lie19-diagnostic.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"  ",true,true)); file.close()
    print("LIE19 GPU PASS ",JSON.stringify({"device":report["device"],"equivalence_cases":comparisons.size(),"maximum_error":max_error,"cached":report["matched_timing_pairs"]["cached"],"forced":report["matched_timing_pairs"]["forced_rebuild"],"external_client":true}))
    lab.queue_free(); await _settle(3); quit(0)
