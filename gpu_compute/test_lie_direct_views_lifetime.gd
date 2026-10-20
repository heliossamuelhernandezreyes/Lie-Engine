extends "res://test_lie_wall12_mobile.gd"
## Additional acceptance of the shipped primary programs through actual
## resolution/RID replacement. Run against the same attributed staged bank.
func run() -> void:
    var lab = load("res://lie_direct_views_lab.tscn").instantiate(); root.add_child(lab); await settle(24)
    check(lab.effect.gpu_ready and lab.effect.direct_renderer!=null,"captured views ready for lifetime acceptance")
    if lab.effect.direct_renderer==null: quit(1); return
    for mode in ["views","views_fast"]:
        lab.command({"op":"set_values","values":{"direct_backend":mode,"internal_resolution":720,"camera_yaw":-74.1162,"camera_elevation":4.4461,"distance_factor":.6}}); await settle()
        var before: Dictionary = await capture(lab.effect)
        lab.command({"op":"set_values","values":{"direct_backend":"regions","internal_resolution":1080}}); await settle()
        lab.command({"op":"set_values","values":{"direct_backend":mode}}); await settle()
        var high: Dictionary = await capture(lab.effect)
        check(high["internal_size"]==1080 and opaque(high)>10000,mode+" real 1080 output after replacement")
        lab.command({"op":"set_values","values":{"internal_resolution":720}}); await settle()
        var after: Dictionary = await capture(lab.effect)
        same(before,after,mode+" restores actual image after 720/1080/backend roundtrip")
        check(before["native_surface"]["surface_world"]==after["native_surface"]["surface_world"],mode+" restores original world positions and owner IDs")
        check(after["cache"]["direct_surface"]["effective_backend"]==mode and after["internal_size"]==720,mode+" no hidden fallback")
    report.merge({"checks":checks,"failed":failed,"scope":"Additional real Vulkan resource-lifetime acceptance of runtime 2836e6b941ae638f4788fe6c28755e7b8bfdc581; not a physical performance result"})
    var file:=FileAccess.open("res://direct-views-lifetime.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    lab.queue_free();await settle();print("CAPTURED VIEWS LIFETIME ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
