extends "res://test_lie_hq_construction.gd"
class SurfaceLab extends "res://lie_construction_proxy_lab.gd":
    pass
func run() -> void:
    var lab:=SurfaceLab.new();lab.output_resolution=256;root.add_child(lab);await settle(20)
    check(lab.metrics.get("configured",false) and lab.state.surface_continuity,"continuous camera path is configured by default")
    check(lab._surface_button.is_visible_in_tree() and lab._inspection_button.is_visible_in_tree(),"surface comparison and full-detail inspection are visible")
    var corrected: Dictionary=await capture(lab)
    check(corrected.get("failure","").is_empty() and not corrected.is_empty(),"actual continuous compositor image")
    lab.command({"op":"set_values","values":{"surface_continuity":false}})
    var legacy: Dictionary=await capture(lab)
    check(legacy.shadow==corrected.shadow and legacy.library_bytes==corrected.library_bytes,"reference and corrected routes retain shadow and immutable sources")
    lab.command({"op":"set_values","values":{"surface_continuity":true}})
    var restored: Dictionary=await capture(lab)
    check(restored.color==corrected.color and restored.depth==corrected.depth,"surface switch restores deterministic corrected image")
    lab.command({"op":"set_values","values":{"surface_probe":true}})
    var instrumented: Dictionary=await capture(lab)
    lab.effect.request_surface_work();var work: Dictionary={}
    for i in range(240):
        await process_frame;work=lab.effect.surface_work()
        if not work.is_empty():break
    check(work.get("available",false) and not work.get("overflow",true) and work.get("footprint_candidates",0)>0,"separate instrumented work probe returns actual counts")
    check(work.get("readback_bytes",0)==32*work.get("banks",[]).size(),"work probe reads exactly 32 bytes per bank")
    check(instrumented.depth==restored.depth and instrumented.color==restored.color,"probe kernels preserve exact image and depth")
    lab.command({"op":"set_values","values":{"surface_probe":false}});await capture(lab)
    lab.inspect_full_brick();var brick: Dictionary=await capture(lab)
    check(lab.state.mode=="asset_scanned_brick" and lab.state.lod==0 and brick.instances==1 and brick.sample_invocations==480000,"inspection uses original full brick LOD with one instance")
    var before: Dictionary=lab.state.duplicate();var revision: int=lab.revision;var frames: int=lab.effect.frame_count
    var rejected: Dictionary=lab.command({"op":"set_values","values":{"mode":"corner","lod":0}})
    check(not rejected.ok and rejected.error=="sample_budget" and lab.state==before and lab.revision==revision and lab.effect.frame_count==frames,"excess scene detail is rejected atomically")
    lab.command({"op":"set_values","values":{"mode":"corner","lod":-1}});await capture(lab)
    var backup: Dictionary=lab.state.duplicate()
    await lab.run_surface_comparison(2)
    var report: Dictionary=lab._latest
    check(report.complete and report.restored and lab.state==backup and report.blocks.size()==8,"A/B/B/A comparison retains all blocks and restores state")
    var probes: int=0
    for block in report.blocks:
        check(not block.before.state.surface_probe,"production timing never enables instrumented counters")
        if block.surface_continuity:
            probes+=1;check(block.surface_work.available and not block.surface_work.overflow,"continuous blocks retain separate work probes")
    check(probes==4,"both continuous rounds and views receive untimed diagnostics")
    var portable: Dictionary=lab.portable_report();var text: String=JSON.stringify(portable,"",false,true)
    check(text.to_utf8_buffer().size()<=24576 and portable.blocks.size()==8,"copied summary is bounded and retains every comparison")
    check(not portable.blocks[0].before.resources.has("camera_plan_profile") and not portable.blocks[0].measurements.has("visibility_planning_rows"),"copied summary omits repeated planner histories")
    check(lab.copy_report() and DisplayServer.clipboard_get()==text,"clipboard success verifies complete roundtrip")
    root.get_texture().get_image().save_png("res://surface-continuity-ui.png")
    var file:=FileAccess.open("res://surface-continuity-mobile.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failed":failed,"report":report,"probe":work,"clipboard_bytes":text.to_utf8_buffer().size(),"physical_android_tested":false},"  "));file.close()
    lab.queue_free();await settle(20);print("SURFACE MOBILE ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
