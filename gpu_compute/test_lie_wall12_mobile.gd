extends "res://test_lie_wall11_mobile.gd"
func take_material(lab,label: String) -> Dictionary:
    var data: Dictionary=await take(lab,label)
    events[label]["raster"]=data["raster_work"]
    return data
func save_material(data: Dictionary,label: String) -> void:
    var image:=Image.create_from_data(data["output_size"],data["output_size"],false,Image.FORMAT_RGBAF,data["color"].to_byte_array());image.convert(Image.FORMAT_RGBA8);image.save_png("res://wall12-"+label+".png")
func linear(data: Dictionary) -> PackedFloat32Array:
    var values: PackedFloat32Array=data["color"].duplicate()
    for i in range(0,values.size(),4):
        for c in range(3):
            var s: float=values[i+c];var x: float=s/12.92 if s<=.04045 else pow((s+.055)/1.055,2.4)
            values[i+c]=x/maxf(1.-x,.0000001)
    return values
func run() -> void:
    var old=load("res://lie_wall11_android_lab.tscn").instantiate();root.add_child(old);await settle(16)
    check(old.effect.gpu_ready,"accepted 0.8 baseline ready")
    if not old.effect.gpu_ready:printerr(old.effect.failure);quit(1);return
    var baseline: Dictionary=await capture(old.effect);old.queue_free();await settle()
    var lab=load("res://lie_wall12_android_lab.tscn").instantiate();root.add_child(lab);await settle(16)
    check(lab.effect.gpu_ready and lab.transport.gpu_ready,"new material pipeline ready")
    if not lab.effect.gpu_ready:printerr(lab.effect.failure);quit(1);return
    lab.command({"op":"set_values","values":{"material_response":false,"bounded_raster":false,"normal_filtering":false,"visibility_diagnostics":true}});await settle()
    var disabled: Dictionary=await take_material(lab,"off");same(baseline,disabled,"new switches OFF preserve 0.8")
    save_material(disabled,"baseline")
    for yaw in [12.,60.,80.]:
        lab.command({"op":"set_values","values":{"camera_yaw":yaw,"bounded_raster":false}});lab.effect.force_geometry_rebuild();await settle();var square: Dictionary=await take_material(lab,"square_"+str(yaw))
        lab.command({"op":"set_values","values":{"bounded_raster":true}});await settle();var tight: Dictionary=await take_material(lab,"tight_"+str(yaw))
        same(square,tight,"bounded footprint preserves color and coverage "+str(yaw))
        check(square["depth"]==tight["depth"],"exact source depth preserved "+str(yaw))
        check(tight["raster_work"]["raster_candidates"]<square["raster_work"]["raster_candidates"] and tight["sample_invocations"]==square["sample_invocations"],"fewer candidate pixels with same genuine source work "+str(yaw))
    lab.command({"op":"set_values","values":{"camera_yaw":12.,"material_response":true,"normal_filtering":true,"lighting_preset":"warm_raking","light_azimuth":-72.,"light_power":1.2}});await settle()
    var material: Dictionary=await take_material(lab,"warm");save_material(material,"warm")
    lab.command({"op":"set_values","values":{"material_response":false}});await settle();var warm_diffuse: Dictionary=await take_material(lab,"warm_diffuse");save_material(warm_diffuse,"warm-diffuse")
    var delta: Dictionary=comparison(material["color"],warm_diffuse["color"]);report["material_delta"]=delta
    check(delta["max"]>.001 and delta["iou"]==1.,"material affects light while preserving silhouette")
    var gc: int=lab.effect.geometry_rebuilds;var allocations: int=lab.effect.allocation_bytes
    lab.command({"op":"set_values","values":{"material_response":true}});await settle();var restored: Dictionary=await take_material(lab,"restored")
    same(material,restored,"material switch roundtrip preserves output")
    check(lab.effect.geometry_rebuilds==gc and queries(restored)==0,"material shading reuses geometry and geometric visibility")
    lab.effect.force_geometry_rebuild();await settle();var rebuilt: Dictionary=await take_material(lab,"cold_geometry");same(restored,rebuilt,"material lighting equals full geometry rebuild")
    lab.command({"op":"set_values","values":{"camera_yaw":60.}});await settle();var angled: Dictionary=await take_material(lab,"angle");save_material(angled,"angle")
    lab.effect.force_geometry_rebuild();await settle();var angle_cold: Dictionary=await take_material(lab,"angle_rebuild");same(angled,angle_cold,"view-dependent material updates on camera change")
    lab.command({"op":"set_values","values":{"camera_yaw":12.,"fill_enabled":false}});await settle();var key: Dictionary=await take_material(lab,"key_only")
    lab.command({"op":"set_values","values":{"key_enabled":false,"fill_enabled":true}});await settle();var fill: Dictionary=await take_material(lab,"fill_only")
    lab.command({"op":"set_values","values":{"key_enabled":true}});await settle();var both: Dictionary=await take_material(lab,"both")
    var k: PackedFloat32Array=linear(key);var f: PackedFloat32Array=linear(fill);var b: PackedFloat32Array=linear(both);var worst: float=0
    for i in range(0,b.size(),4):
        if b[i+3]<.99:continue
        for c in range(3):worst=maxf(worst,absf(k[i+c]+f[i+c]-b[i+c]))
    report["source_superposition_linear_max"]=worst;check(worst<.0002,"independent warm/cool directions sum in linear radiance")
    lab.command({"op":"set_values","values":{"key_enabled":false,"fill_enabled":false}});await settle();var black: Dictionary=await take_material(lab,"black")
    var energy: float=0
    for i in range(0,black["color"].size(),4):energy=maxf(energy,maxf(black["color"][i],maxf(black["color"][i+1],black["color"][i+2])))
    check(energy<.00001,"no invented ambient or specular when sources are off")
    var before_filter_geometry: int=lab.effect.geometry_rebuilds
    lab.command({"op":"set_values","values":{"key_enabled":true,"fill_enabled":true,"normal_filtering":false}});await settle();var unfiltered: Dictionary=await take_material(lab,"unfiltered");save_material(unfiltered,"unfiltered")
    lab.command({"op":"set_values","values":{"normal_filtering":true}});await settle();var filtered: Dictionary=await take_material(lab,"filtered")
    check(lab.effect.geometry_rebuilds==before_filter_geometry and comparison(unfiltered["color"],filtered["color"])["iou"]==1.,"normal variance changes shading without geometry work")
    # Interleaved same-camera, warm-cache geometry solves. Raw per-pass rows
    # retain event serial/options; no FPS claim from a software Vulkan device.
    var benchmark: Array=[]
    lab.command({"op":"set_values","values":{"visibility_diagnostics":false,"material_response":false}});await settle()
    for pass_index in range(6):
        var fast: bool=pass_index%2==1
        lab.command({"op":"set_values","values":{"bounded_raster":fast}});lab.effect.force_geometry_rebuild();await settle()
        benchmark.append({"serial":lab.effect.frame_count,"bounded":fast,"material":false})
    lab.command({"op":"set_values","values":{"material_response":true,"bounded_raster":true}});await settle();var final: Dictionary=await take_material(lab,"shipping")
    check(not final["raster_work"]["instrumented"] and not final["visibility_work"]["instrumented"],"shipping defaults omit work instrumentation")
    check(lab.effect.asset_uploads==1 and lab.effect.allocation_bytes==allocations and final["instances"]==97 and lab.agent_snapshot()["collider_count"]==1 and lab.agent_snapshot()["metrics"]["visible_source_meshes"]==0,"same bank, memory budget and single invisible collider")
    var frames: int=lab.effect.frame_count;await settle(12);check(lab.effect.frame_count==frames,"idle image remains cached")
    report.merge({"checks":checks,"failed":failed,"device":final["device"],"events":events,"benchmark_serials":benchmark,"cache":final["cache"],"passes":final["passes"],"appearance_requested_bytes":final["allocation_bytes"],"transport_requested_bytes":lab.transport.allocation_bytes,"source_bank_sha256":lab.effect.catalog["sha256"],"physical_android_tested":false})
    var file:=FileAccess.open("res://wall12-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
    lab.queue_free();await settle();print("WALL12 ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
