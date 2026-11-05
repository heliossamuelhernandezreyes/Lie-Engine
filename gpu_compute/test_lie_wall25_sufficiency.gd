extends "res://test_lie_native_depth.gd"
## Minimal real-Vulkan data capture for geometric sufficiency at ONE phone pose.
## No benchmark, no change to the production renderer and no Android APK.

func run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://native-depth"))
    var lab=load("res://lie_direct_views_lab.tscn").instantiate()
    root.add_child(lab)
    await settle(24)
    check(lab.effect.gpu_ready and lab.effect.direct_renderer!=null,"WALL06 real native Vulkan initialized")
    if lab.effect.direct_renderer==null:
        printerr("EFFECT FAILURE ",lab.effect.failure," / ",lab.effect.direct_failure)
        quit(1);return
    var pose: Dictionary={
        "camera_yaw":-72.90939846038818,
        "camera_elevation":2.0563994513617607,
        "distance_factor":.6,
        "light_azimuth":-53.4,
        "light_power":1.,
        "fill_enabled":true,
        "fill_power":.32,
        "fill_azimuth":55.,
        "key_enabled":true,
        "exposure":2.,
        "lighting_preset":"neutral",
        "internal_resolution":720,
        "shadows":false
    }
    check(lab.command({"op":"set_values","values":pose})["ok"],"exact phone pose accepted")
    var rows: Array=[]
    for mode in ["regions","native"]:
        check(lab.command({"op":"set_values","values":{"direct_backend":mode}})["ok"],"backend "+mode)
        await settle()
        var data: Dictionary=await capture(lab.effect)
        check(data.has("native_surface") and lab.effect.effective_direct_backend==mode,
              "actual "+mode+" readback, no fallback")
        if not data.has("native_surface"):quit(1);return
        dump_frame(data,"0-"+mode)
        rows.append({"backend":mode,"device":data["device"],"internal_size":data["internal_size"],
                     "effective_backend":lab.effect.effective_direct_backend})
        print("LIE25 SUFFICIENCY ",mode," ",data["device"])
    var file:=FileAccess.open("res://native-depth/execution.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failed":failed,"frames":rows,
        "scope":"one exact failing phone camera, original bank, untimed software Vulkan; no source-mesh equivalence or FPS claim"},"  ",true,true))
    file.close()
    lab.queue_free()
    await settle()
    print("LIE25 SUFFICIENCY ",checks," ",("FAIL" if failed else "PASS"))
    quit(1 if failed else 0)
