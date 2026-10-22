extends "res://test_lie_direct_views_gpu.gd"
# Untimed native Vulkan evidence at the user's failing camera and nearby
# motion. Attribution/packet identities are checked by the production loader.

func dump_frame(data: Dictionary, label: String) -> void:
    var prefix: String = "res://native-depth/"+label
    var native: Dictionary = data["native_surface"]
    for pair in [["world",native["surface_world"].to_byte_array()],["depth",native["native_depth"].to_byte_array()],["rgba",data["color"].to_byte_array()],["normal",native["surface_normal_half"]],["material",native["surface_color_half"]],["views",native["view_packet"]],["proxies",native["proxy_packet"]]]:
        var file := FileAccess.open(prefix+"-"+pair[0]+".bin",FileAccess.WRITE)
        file.store_buffer(pair[1]); file.close()
    var image := Image.create_from_data(data["output_size"],data["output_size"],false,Image.FORMAT_RGBAF,data["color"].to_byte_array())
    image.convert(Image.FORMAT_RGBA8); image.save_png(prefix+".png")

func run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://native-depth"))
    var lab = load("res://lie_direct_views_lab.tscn").instantiate(); root.add_child(lab); await settle(24)
    check(lab.effect.gpu_ready and lab.effect.direct_renderer!=null,"real attributed-bank native Vulkan initialization")
    if lab.effect.direct_renderer==null: printerr(lab.effect.failure," / ",lab.effect.direct_failure); quit(1); return
    var pose: Dictionary = {"camera_yaw":-72.90939846038818,"camera_elevation":2.0563994513617607,"distance_factor":.6,"light_azimuth":-53.4,"light_power":1.,"fill_enabled":true,"fill_power":.32,"fill_azimuth":55.,"key_enabled":true,"exposure":2.,"lighting_preset":"neutral","internal_resolution":720,"shadows":false}
    check(lab.command({"op":"set_values","values":pose})["ok"],"exact phone camera through validated command")
    var poses: Array = [{"camera_yaw":-72.90939846038818},{"camera_yaw":-73.00939846038818},{"camera_yaw":-72.80939846038818}]
    if OS.get_environment("LIE_NATIVE_FULL")=="1":
        poses.append_array([{"camera_yaw":12.,"camera_elevation":9.,"distance_factor":1.},{"camera_yaw":80.},{"camera_yaw":160.},{"camera_yaw":35.,"camera_elevation":70.,"distance_factor":.6}])
    var rows: Array = []
    for index in range(poses.size()):
        check(lab.command({"op":"set_values","values":poses[index]})["ok"],"camera "+str(index))
        for mode in ["regions","native"]:
            check(lab.command({"op":"set_values","values":{"direct_backend":mode}})["ok"],"select "+mode)
            await settle()
            var data: Dictionary = await capture(lab.effect)
            check(data.has("native_surface") and lab.effect.effective_direct_backend==mode,"actual "+mode+" without fallback")
            if not data.has("native_surface"): quit(1); return
            dump_frame(data,str(index)+"-"+mode)
            rows.append({"pose":lab.state.duplicate(true),"mode":mode,"device":data["device"],"internal_size":data["internal_size"],"metrics":data["cache"]["direct_surface"]})
            print("NATIVE FRAME ",index," ",mode," ",data["device"])
    lab.command({"op":"set_values","values":pose}); await settle()
    for mode in ["regions","native"]:
        lab.command({"op":"set_values","values":{"direct_backend":mode,"shadows":true}}); await settle()
        dump_frame(await capture(lab.effect),"phone-shadows-"+mode)
    await validate_lifetime(lab,"native")
    var file := FileAccess.open("res://native-depth/execution.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failed":failed,"frames":rows,"scope":"untimed software Vulkan; regions comparison is not source ground truth; no mobile speed or photo-fidelity claim"},"  ",true,true)); file.close()
    lab.queue_free(); await settle()
    print("NATIVE DEPTH ",checks," ","FAIL" if failed else "PASS"); quit(1 if failed else 0)
