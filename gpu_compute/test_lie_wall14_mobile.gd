extends "res://test_lie_wall12_mobile.gd"
func run() -> void:
    var old=load("res://lie_wall13_android_lab.tscn").instantiate();root.add_child(old);await settle(16)
    var baseline: Dictionary=await capture(old.effect);old.queue_free();await settle()
    var lab=load("res://lie_wall14_android_lab.tscn").instantiate();root.add_child(lab);await settle(16)
    check(lab.effect.gpu_ready and lab.transport.gpu_ready,"diagnostic runtime ready")
    if not lab.effect.gpu_ready:quit(1);return
    var current: Dictionary=await take(lab,"baseline");same(baseline,current,"diagnostics preserve shipping image")
    var backup: Dictionary=lab.state.duplicate(true);var uploads: int=lab.effect.asset_uploads
    check(lab.command({"op":"diagnose"})["ok"],"current-mode diagnostic starts")
    for i in range(5000):
        await process_frame
        if not lab.benchmark_busy:break
    var diagnostic: Dictionary=lab._diagnostic_report;report["diagnostic"]=diagnostic
    check(not lab.benchmark_busy and diagnostic.get("events",[]).size()==9 and diagnostic.get("error","")=="" and diagnostic.get("restored",false) and lab.state==backup,"nine real GPU events restore exact state")
    check(diagnostic.get("gpu_analysis",{}).get("available",false),"real GPU stage ranking available")
    check(not diagnostic.get("transport_rows",[]).is_empty(),"real transport timing included")
    await settle();var restored: Dictionary=await take(lab,"restored");same(current,restored,"diagnostic roundtrip preserves image")
    lab._show_report();await lab._copy_report()
    check(DisplayServer.clipboard_get()==lab._report_content,"report clipboard roundtrip on native display")
    check(lab._report_text.text.contains("lie-mobile-diagnostics/1"),"selectable fallback remains available")
    check(lab.effect.asset_uploads==uploads and lab.agent_snapshot()["collider_count"]==1,"no bank reupload or new wall collider")
    report.merge({"checks":checks,"failed":failed,"physical_android_tested":false,"device":current["device"]})
    var file:=FileAccess.open("res://wall14-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    lab.queue_free();await settle();print("WALL14 ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
