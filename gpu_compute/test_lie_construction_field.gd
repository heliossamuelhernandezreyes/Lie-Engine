extends "res://test_lie_hq_construction.gd"
func field_data(lab: Node) -> Dictionary:
    lab.transport.request_readback()
    for i in range(240):
        await process_frame
        var data: Dictionary=lab.transport.readback()
        if not data.is_empty():return data
    check(false,"field readback");return {}
func peak_positive(a: PackedFloat32Array,b: PackedFloat32Array) -> float:
    var result: float=0.
    for i in range(a.size()):result=maxf(result,a[i]-b[i])
    return result
func run() -> void:
    var lab=load("res://lie_hq_construction_lab.tscn").instantiate();lab.state.yaw=-25.;root.add_child(lab);await settle(20)
    check(lab.metrics.get("configured",false),"field assembly configured: "+str(lab.metrics))
    if not lab.metrics.get("configured",false):lab.queue_free();await settle();quit(1);return
    var both: Dictionary=await capture(lab);save(both,"field-corner-both");var flux: Dictionary=await field_data(lab)
    check(both.field.ready and both.field.nodes>1024 and lab.transport._output_dimensions().y>1,"real multi-row field beyond 1024 source-owned patches")
    var f:=FileAccess.open("res://construction-field-model.json",FileAccess.WRITE);f.store_string(JSON.stringify(lab.light_model,"  "));f.close()
    f=FileAccess.open("res://construction-field-flux.f32",FileAccess.WRITE);f.store_buffer(flux.flux.to_byte_array());f.close()
    var io: int=both.page_io_bytes;var uploads: int=both.asset_uploads;var revision: int=lab.revision;var solves: int=lab.transport.frame_count
    lab.command({"op":"set_values","values":{"indirect":false}});var direct: Dictionary=await capture(lab);save(direct,"field-corner-direct")
    check(both.depth==direct.depth and difference(both.color,direct.color)>.00001,"indirect affects radiance without changing captured geometry")
    check(lab.transport.frame_count==solves and direct.page_io_bytes==io and direct.asset_uploads==uploads,"indirect switch reuses field and exact source pages")
    lab.command({"op":"set_values","values":{"bounces":0,"indirect":true}});var zero: Dictionary=await capture(lab)
    lab.command({"op":"set_values","values":{"indirect":false}});var zero_off: Dictionary=await capture(lab)
    check(difference(zero.color,zero_off.color)<.00001,"zero bounces cannot double count the direct field")
    lab.command({"op":"set_values","values":{"bounces":2,"indirect":true,"fill_enabled":false}});await capture(lab);var key: Dictionary=await field_data(lab)
    lab.command({"op":"set_values","values":{"fill_enabled":true,"key_enabled":false}});await capture(lab);var fill: Dictionary=await field_data(lab);var superposition: float=0.
    for i in range(flux.flux.size()):superposition=maxf(superposition,absf(flux.flux[i]-key.flux[i]-fill.flux[i]))
    check(superposition<.00003,"construction GPU preserves per-source superposition")
    lab.command({"op":"set_values","values":{"key_enabled":false,"fill_enabled":false,"ambient":0.}});var dark: Dictionary=await capture(lab);var off: Dictionary=await field_data(lab);var max_flux: float=0.;var max_rgb: float=0.
    for value in off.flux:max_flux=maxf(max_flux,absf(value))
    for i in range(0,dark.color.size(),4):
        for c in range(3):max_rgb=maxf(max_rgb,absf(dark.color[i+c]))
    check(max_flux==0. and max_rgb==0. and dark.depth==both.depth,"disabled sources leave no residual field energy")
    lab.command({"op":"set_values","values":{"key_enabled":true,"fill_enabled":true,"ambient":1.}});var restored: Dictionary=await capture(lab)
    check(difference(restored.color,both.color)<.00001,"light restoration returns the same image")
    var previous_solves: int=lab.transport.frame_count;var before: int=lab.effect.frame_count;await settle(12)
    check(lab.transport.frame_count==previous_solves and lab.effect.frame_count==before,"idle field and appearance stay cached")
    lab.command({"op":"set_values","values":{"yaw":-30.}});await capture(lab)
    check(lab.transport.frame_count==previous_solves and lab.effect.page_io_bytes==io,"camera movement does not rebuild topology, solve light or reload source pages")
    var mapping: PackedByteArray=lab.transport.get_meta("mapping").duplicate();mapping.encode_u32(16,mapping.decode_u32(16)+1)
    check(not lab.effect.bind_field(lab.transport,mapping,lab.effect._pending.instances,lab.effect.manifest.scene_identity),"cross-face owner mapping rejected")
    var invalid_revision: int=lab.revision
    for bad in [{"indirect":1},{"bounces":true},{"fill_power":NAN},{"ambient":3.}]:check(not lab.command({"op":"set_values","values":bad}).ok and lab.revision==invalid_revision,"invalid lighting transaction remains atomic")
    for mode in ["opening","roof","door"]:
        lab.command({"op":"set_values","values":{"mode":mode,"yaw":-25.}});var a: Dictionary=await capture(lab);save(a,"field-"+mode)
        check(a.field.ready and a.failure.is_empty(),"field rebind after module switch: "+mode)
    var closed: Dictionary=await capture(lab)
    lab.command({"op":"set_values","values":{"door_angle":75.}});var opened: Dictionary=await capture(lab);save(opened,"field-door-open")
    check(opened.field.ready and opened.field.producer!=closed.field.producer and opened.depth!=closed.depth,"door pose replaces immutable field with matching ownership")
    var door_io: int=opened.page_io_bytes;var door_uploads: int=opened.asset_uploads
    lab.command({"op":"set_values","values":{"door_angle":20.}});var moved: Dictionary=await capture(lab)
    check(moved.field.ready and moved.page_io_bytes==door_io and moved.asset_uploads==door_uploads,"door motion preserves source-bank residency")
    lab.transport.shutdown();await settle(12);var released: Dictionary=await capture(lab)
    check(not released.field.ready and released.failure.is_empty(),"released producer cannot leave a borrowed field descriptor active")
    var report: Dictionary={"checks":checks,"failed":failed,"source_superposition_max_error":superposition,"corner":both.duplicate(),"physical_android_tested":false};report.corner.erase("color");report.corner.erase("depth");report.corner.erase("shadow")
    f=FileAccess.open("res://construction-field-native.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
    lab.queue_free();await settle(20);print("CONSTRUCTION FIELD ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
