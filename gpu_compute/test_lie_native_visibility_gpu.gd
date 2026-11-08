extends "res://test_lie_hq_construction.gd"
class ProofEffect extends "res://lie_construction_scene_effect.gd":
    var _proof_ready: bool=false
    func request_readback() -> void:
        _mutex.lock();_proof_ready=false;_mutex.unlock();super.request_readback()
    func readback() -> Dictionary:
        _mutex.lock();var ready: bool=_proof_ready;_mutex.unlock()
        return super.readback() if ready else {}
    func _capture() -> void:
        super._capture()
        if not gpu_ready:return
        var proof: Dictionary={}
        for binding in [5,7]:
            var bytes: PackedByteArray=_rd.buffer_get_data(_buffers[binding]);var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);proof[str(binding)]=hash.finish().hex_encode()
        _mutex.lock();_readback.proof=proof;_proof_ready=true;_mutex.unlock()
class NativeLab extends "res://lie_construction_proxy_lab.gd":
    func _create_effect() -> CompositorEffect:return ProofEffect.new(output_resolution)

func run() -> void:
    check(ClassDB.class_exists("LieVisibilityPlanner"),"actual native visibility GDExtension class loaded")
    if failed:quit(1);return
    var lab:=NativeLab.new();lab.output_resolution=256;root.add_child(lab);await settle(20)
    var views: Array=[
        {"name":"whole","mode":"corner","yaw":-25.,"elevation":22.,"zoom":1.,"focus_x":0.,"focus_y":0.,"seed":2102},
        {"name":"close","mode":"corner","yaw":0.,"elevation":0.,"zoom":.25,"focus_x":.6,"focus_y":0.},
        {"name":"window","mode":"corner","yaw":0.,"elevation":0.,"zoom":.25,"focus_x":-.1,"focus_y":.1},
        {"name":"back","mode":"corner","yaw":180.,"elevation":0.,"zoom":.25,"focus_x":-.6,"focus_y":0.,"seed":7319},
        {"name":"grazing","mode":"corner","yaw":89.99,"elevation":0.,"zoom":1.,"focus_x":0.,"focus_y":0.},
        {"name":"overhead","mode":"corner","yaw":10.,"elevation":90.,"zoom":.25,"focus_x":0.,"focus_y":0.},
        {"name":"empty","mode":"corner","yaw":0.,"elevation":0.,"zoom":.25,"focus_x":3.,"focus_y":3.},
        {"name":"door","mode":"door","door_angle":75.,"yaw":15.,"elevation":5.,"zoom":.25,"focus_x":.5,"focus_y":0.},
        {"name":"roof","mode":"roof","yaw":-145.,"elevation":30.,"zoom":.25,"focus_x":.7,"focus_y":.3}]
    var results: Array=[];var reduced: int=0
    for view in views:
        var values: Dictionary=view.duplicate();var name: String=values.name;values.erase("name");values.camera_guard=false;values.camera_culling=true;values.cluster_culling=false;values.reverse_banks=false
        check(lab.command({"op":"set_values","values":values}).ok and lab.metrics.get("configured",false),"reference native scene "+name)
        var reference: Dictionary=await capture(lab);var solves: int=lab.transport.frame_count
        lab.command({"op":"set_values","values":{"cluster_culling":true}});var selected: Dictionary=await capture(lab)
        check(selected.camera_plan.get("enabled",false),"verified metadata and native planner active "+name)
        check(reference.color==selected.color and reference.depth==selected.depth and reference.shadow==selected.shadow and reference.proof==selected.proof,"complete RGBA/depth/shadow/winner/material equality "+name)
        check(selected.camera_samples<=reference.camera_samples and selected.camera_plan.backface_skipped_samples==reference.camera_samples-selected.camera_samples,"selected sample counts reconcile "+name)
        check(lab.transport.frame_count==solves and selected.shadow_samples==selected.sample_invocations,"full shadow and lighting owners retained "+name)
        if selected.camera_samples<reference.camera_samples:reduced+=1
        if name in ["whole","door"]:
            lab.command({"op":"set_values","values":{"reverse_banks":true}});var reversed: Dictionary=await capture(lab)
            check(reversed.color==selected.color and reversed.depth==selected.depth and reversed.shadow==selected.shadow and reversed.proof==selected.proof,"native ranges preserve bank order ownership "+name)
        results.append({"name":name,"reference_samples":reference.camera_samples,"selected_samples":selected.camera_samples,"logical_samples":selected.sample_invocations,"native_plan":selected.camera_plan,"proof":selected.proof,"exact":reference.color==selected.color and reference.depth==selected.depth and reference.shadow==selected.shadow and reference.proof==selected.proof})
        save(selected,"native-visibility-"+name)
    check(reduced>=2,"native intervals remove real camera work in multiple views")
    var saved_recipe: Dictionary=lab.recipe.duplicate(true)
    var saved_lod: int=lab.state.lod
    lab.recipe.instances=[]
    for i in range(10):lab.recipe.instances.append(saved_recipe.instances[0])
    lab.state.lod=0
    var over_budget: Dictionary=lab._build_geometry()
    # Use enough original entries to exceed the chosen LOD budget.
    if not over_budget.has("error"):
        for i in range(100):lab.recipe.instances.append(saved_recipe.instances[0])
        over_budget=lab._build_geometry()
    check(over_budget.has("error"),"excess detail reports a budget error instead of silently lowering source LOD")
    lab.recipe=saved_recipe;lab.state.lod=saved_lod
    var revision: int=lab.revision
    check(not lab.command({"op":"set_values","values":{"cluster_culling":1}}).ok and lab.revision==revision,"native selection boolean validated atomically")
    check(lab.command({"op":"set_resolution","value":960}).ok,"default full resolution accepted")
    lab.command({"op":"set_values","values":{"mode":"corner","seed":2102,"yaw":-25.,"elevation":22.,"zoom":1.,"focus_x":0.,"focus_y":0.,"cluster_culling":false,"reverse_banks":false}})
    var full: Dictionary=await capture(lab)
    lab.command({"op":"set_values","values":{"cluster_culling":true}});var selected: Dictionary=await capture(lab)
    var quality: Dictionary={"output":selected.output_size,"internal":selected.internal_size,"reference_samples":full.camera_samples,"selected_samples":selected.camera_samples,"projection_capacity":selected.projection_capacity,"projection_stride":selected.projection_stride,"projection_bytes":selected.projection_bytes,"projection_saved_bytes":selected.projection_capacity*16,"native_plan":selected.camera_plan,"rgba_exact":full.color==selected.color,"depth_exact":full.depth==selected.depth,"shadow_exact":full.shadow==selected.shadow,"winner_material_exact":full.proof==selected.proof}
    check(quality.output==960 and quality.internal==1920 and quality.rgba_exact and quality.depth_exact and quality.shadow_exact and quality.winner_material_exact and quality.selected_samples<quality.reference_samples,"default 960/1920 native visibility retains exact full buffers")
    check(quality.projection_stride==64 and quality.projection_bytes==quality.projection_capacity*64,"lossless 64-byte projection allocation measured")
    var limits: Dictionary=await lab._sync_metrics()
    check(limits.device_limits.range_source=="VkPhysicalDeviceProperties" and limits.device_limits.max_storage_buffer_range>=limits.projection_bytes,"actual device storage limits queried before allocation")
    lab.command({"op":"set_resolution","value":256});await settle(12)
    var backup: Dictionary=lab.state.duplicate();await lab.run_cluster_comparison(2)
    var report: Variant=JSON.parse_string(DisplayServer.clipboard_get())
    check(lab.state==backup and report is Dictionary and report.complete and report.restored and report.kind=="native_backface_clusters_A_B_B_A" and report.blocks.size()==8,"native A/B/B/A benchmark restores controls and copies full report")
    var has_planning: bool=false
    for block in report.blocks:
        if block.clusters_enabled:has_planning=has_planning or block.measurements.visibility_planning_cpu_ms.samples>0
    check(has_planning,"benchmark records actual native planning CPU separately")
    root.get_texture().get_image().save_png("res://construction-native-visibility-ui.png")
    var file:=FileAccess.open("res://construction-native-visibility.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"cases":results,"reduced_cases":reduced,"full_quality":quality,"report":report,"physical_android_tested":false},"  "));file.close()
    lab.queue_free();await settle(20);print("NATIVE VISIBILITY GPU ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
