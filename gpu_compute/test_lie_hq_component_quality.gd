extends "res://test_lie_hq_construction.gd"
func run() -> void:
    var lab=load("res://lie_hq_construction_lab.tscn").instantiate();lab.state.mode="asset_mortar_bed";root.add_child(lab);await settle(18)
    check(lab.effect.capture_loaded,"quality source contracts")
    if not lab.effect.capture_loaded:lab.queue_free();await settle();quit(1);return
    for bank in lab.effect.banks:
        if bank.name=="brick":continue
        for name in bank.catalog.masters:
            for side in ["front","back"]:
                var prefix: String="quality_"+name+"_"+side
                check(lab.command({"op":"set_values","values":{"mode":"asset_"+name,"yaw":25. if side=="front" else -145.,"elevation":18.,"light":-35. if side=="front" else 55.,"normals":true,"shadows":false,"lod":0,"zoom":1.}}).ok,"quality pose")
                var data: Dictionary=await capture(lab);save(data,prefix)
                for field in ["color","depth"]:
                    var f:=FileAccess.open("res://"+prefix+"-"+field+".f32",FileAccess.WRITE);f.store_buffer(data[field].to_byte_array());f.close()
                var p:=FileAccess.open("res://"+prefix+"-parameters.bin",FileAccess.WRITE);p.store_buffer(lab.effect._pending.parameters);p.close()
                check(lab.metrics.configured and data.banks==5,"quality actual bank capture")
                print("QUALITY CAPTURE ",prefix)
    var f:=FileAccess.open("res://component-quality-native.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failed":failed,"views":24,"physical_android_tested":false},"  "));f.close()
    lab.queue_free();await settle(16);print("COMPONENT QUALITY ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
