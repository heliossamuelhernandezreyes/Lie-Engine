extends "res://test_lie_wall07_mobile.gd"
# Reproduce the 2026-10-21 phone pose using the original 2.5 production modules.
# Outputs are untimed evidence. Software Vulkan is not phone performance.

func write_bytes(path: String, bytes: PackedByteArray) -> void:
    var f := FileAccess.open("res://diagnosis/" + path, FileAccess.WRITE)
    f.store_buffer(bytes)
    f.close()

func write_json(path: String, value: Dictionary) -> void:
    var f := FileAccess.open("res://diagnosis/" + path, FileAccess.WRITE)
    f.store_string(JSON.stringify(value, "  ", true, true))
    f.close()

func run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://diagnosis"))
    var lab = load("res://lie_direct_views_lab.tscn").instantiate()
    root.add_child(lab)
    await settle(24)
    if not lab.effect.gpu_ready:
        printerr("NOT READY ", lab.effect.failure)
        quit(1)
        return
    var pose: Dictionary = {"camera_yaw":-72.90939846038818,"camera_elevation":2.0563994513617607,"distance_factor":.6,"light_azimuth":-53.400000000000006,"light_power":1.,"fill_enabled":true,"fill_power":.32,"fill_azimuth":55.,"key_enabled":true,"exposure":2.,"lighting_preset":"neutral","internal_resolution":720}
    var accepted: Dictionary = lab.command({"op":"set_values","values":pose})
    if not accepted.get("ok",false):
        printerr("POSE REJECTED ", accepted)
        quit(1)
        return
    await settle()
    for mode in ["regions", "views", "views_fast"]:
        for shadows in [true, false]:
            var command_result: Dictionary = lab.command({"op":"set_values","values":{"direct_backend":mode,"shadows":shadows}})
            await settle()
            var data: Dictionary = await capture(lab.effect)
            if data.is_empty() or not data.has("native_surface") or lab.effect.effective_direct_backend != mode:
                printerr("NATIVE READBACK MISSING ", mode)
                quit(1)
                return
            var label: String = mode + ("-shadows" if shadows else "-no-shadows")
            var native: Dictionary = data["native_surface"]
            var rgba: PackedFloat32Array = data["color"]
            var image := Image.create_from_data(data["output_size"], data["output_size"], false, Image.FORMAT_RGBAF, rgba.to_byte_array())
            image.convert(Image.FORMAT_RGBA8)
            image.save_png("res://diagnosis/"+label+".png")
            write_bytes(label+"-rgba.f32",rgba.to_byte_array())
            write_bytes(label+"-world.f32",native["surface_world"].to_byte_array())
            write_bytes(label+"-color.f16",native["surface_color_half"])
            write_bytes(label+"-normal.f16",native["surface_normal_half"])
            write_bytes(label+"-depth.f32",native["native_depth"].to_byte_array())
            write_json(label+".json",{"mode":mode,"shadows":shadows,"state":lab.state,"command":command_result,"device":data["device"],"internal_size":data["internal_size"],"output_size":data["output_size"],"metrics":data["cache"]["direct_surface"]})
            print("DIAGNOSED ",label," ",data["device"]," native: ",native["surface_world"].size())
    lab.queue_free()
    await settle()
    quit(0)
