extends "res://test_lie_hq_construction.gd"
func run() -> void:
    var lab=load("res://lie_construction_proxy_lab.tscn").instantiate();lab.output_resolution=256;root.add_child(lab);await settle(20)
    var cases: Array=[];var reduced: int=0;var zero: int=0
    var views: Array=[
        {"name":"whole","mode":"corner","yaw":-25.,"elevation":22.,"zoom":1.,"focus_x":0.,"focus_y":0.},
        {"name":"close_edge","mode":"corner","yaw":0.,"elevation":0.,"zoom":.25,"focus_x":.6,"focus_y":0.},
        {"name":"close_window","mode":"corner","yaw":0.,"elevation":0.,"zoom":.25,"focus_x":-.10,"focus_y":.1},
        {"name":"back","mode":"corner","seed":7319,"yaw":180.,"elevation":0.,"zoom":.25,"focus_x":-.6,"focus_y":0.},
        {"name":"overhead","mode":"corner","yaw":10.,"elevation":90.,"zoom":.25,"focus_x":0.,"focus_y":0.},
        {"name":"empty","mode":"corner","yaw":0.,"elevation":0.,"zoom":.25,"focus_x":3.,"focus_y":3.},
        {"name":"open_door","mode":"door","door_angle":75.,"yaw":15.,"elevation":5.,"zoom":.25,"focus_x":.5,"focus_y":0.},
        {"name":"roof","mode":"roof","yaw":-145.,"elevation":30.,"zoom":.25,"focus_x":.7,"focus_y":.3}]
    for view in views:
        var values: Dictionary=view.duplicate();var name: String=values.name;values.erase("name");values.camera_guard=false;values.camera_culling=false;values.reverse_banks=false
        check(lab.command({"op":"set_values","values":values}).ok,"baseline camera "+name)
        check(lab.metrics.get("configured",false),"current scene configures its own renderer and light field "+name)
        var full: Dictionary=await capture(lab);var solves: int=lab.transport.frame_count
        lab.command({"op":"set_values","values":{"camera_culling":true}});var selected: Dictionary=await capture(lab)
        var peak: float=difference(full.color,selected.color)
        if name=="close_edge":
            lab.command({"op":"set_values","values":{"reverse_banks":true}});var cold: Dictionary=await capture(lab)
            check(cold.color==full.color and cold.depth==full.depth and cold.shadow==full.shadow,"independent cold shadow pass keeps offscreen casters with camera selection")
        check(peak==0. and full.depth==selected.depth and full.shadow==selected.shadow,"camera selection exact RGBA, depth and shadow "+name)
        check(lab.transport.frame_count==solves and full.sample_invocations==selected.sample_invocations and selected.shadow_samples==selected.sample_invocations,"camera culling preserves all lighting owners and full shadow jobs "+name)
        check(selected.camera_samples<=full.camera_samples and full.camera_samples==full.sample_invocations,"camera dispatch counts report actual selected work "+name)
        if selected.camera_samples<full.camera_samples:reduced+=1
        if selected.camera_samples==0:zero+=1
        save(selected,"hierarchy-case-"+name)
        cases.append({"name":name,"full_samples":full.camera_samples,"camera_samples":selected.camera_samples,"shadow_samples":selected.shadow_samples,"camera_jobs":selected.camera_jobs,"hierarchy":lab.metrics.visibility.duplicate(),"rgba_error":peak,"depth_exact":full.depth==selected.depth,"shadow_exact":full.shadow==selected.shadow})
    check(reduced>=4,"close and displaced views actually skip camera work")
    check(zero>=1,"empty frustum dispatches zero camera jobs without stale pixels")
    var revision: int=lab.revision
    check(not lab.command({"op":"set_values","values":{"camera_culling":1}}).ok and lab.revision==revision,"selection boolean validated atomically")
    var before: Dictionary=lab.effect._pending.duplicate(true)
    check(not lab.effect.configure_view(before.parameters,before.instances,before.jobs,before.work,PackedByteArray([2])) and lab.effect._pending==before,"invalid visibility packet leaves renderer transaction intact")
    var backup: Dictionary=lab.state.duplicate();await lab.run_visibility_comparison(2)
    check(lab._latest.complete and lab._latest.restored and lab.state==backup and lab._latest.blocks.size()==4,"paired visibility benchmark restores controls")
    var copied: Variant=JSON.parse_string(DisplayServer.clipboard_get())
    check(copied is Dictionary and copied.kind=="hierarchical_camera_selection_A_B" and copied.complete,"visibility benchmark automatically copies completed report")
    for block in lab._latest.blocks:
        check(block.after.resources.shadow_samples==block.after.resources.samples and block.after.resources.camera_samples<=block.after.resources.samples,"benchmark exposes separate camera and shadow workloads")
    check(lab.command({"op":"set_resolution","value":960}).ok,"full-quality visibility resolution accepted explicitly")
    lab.command({"op":"set_values","values":{"mode":"corner","seed":2102,"yaw":0.,"elevation":0.,"zoom":.25,"focus_x":.6,"focus_y":0.,"camera_culling":false}})
    var full_quality: Dictionary=await capture(lab)
    lab.command({"op":"set_values","values":{"camera_culling":true}});var selected_quality: Dictionary=await capture(lab)
    var quality: Dictionary={"output":selected_quality.output_size,"internal":selected_quality.internal_size,"logical_samples":selected_quality.sample_invocations,"camera_samples":selected_quality.camera_samples,"shadow_samples":selected_quality.shadow_samples,"rgba_exact":full_quality.color==selected_quality.color,"depth_exact":full_quality.depth==selected_quality.depth,"shadow_exact":full_quality.shadow==selected_quality.shadow}
    check(quality.output==960 and quality.internal==1920 and quality.rgba_exact and quality.depth_exact and quality.shadow_exact and quality.camera_samples<quality.logical_samples,"default 960/1920 quality preserves exact pixels while skipping offscreen jobs")
    lab.command({"op":"set_values","values":{"yaw":-25.,"elevation":22.,"zoom":1.,"focus_x":0.,"focus_y":0.}});await capture(lab);await lab._sync_metrics();await settle(12)
    root.get_texture().get_image().save_png("res://construction-hierarchy-ui.png")
    var file:=FileAccess.open("res://construction-hierarchy-native.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"cases":cases,"reduced_cases":reduced,"zero_work_cases":zero,"full_quality":quality,"report":copied,"physical_android_tested":false},"  "));file.close()
    lab.queue_free();await settle(20);print("HIERARCHY GPU ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
