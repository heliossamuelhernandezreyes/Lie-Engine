extends SceneTree
## Exercise the actual captured compositor and the shared GPU transport.
var checks: int=0
var failed: bool=false
var results: Dictionary={}
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("BRICK REFERENCE FAIL ",label)
func settle(frames: int=8) -> void:
    for i in range(frames):await process_frame
func capture(lab: Node3D) -> Dictionary:
    await settle()
    lab.effect.request_readback()
    for i in range(180):
        await process_frame
        var data: Dictionary=lab.effect.readback()
        if not data.is_empty():return data
    check(false,"readback timeout");return {}
func save(data: Dictionary,name: String) -> void:
    var file:=FileAccess.open("res://"+name+".rgba32f",FileAccess.WRITE);file.store_buffer(data.color.to_byte_array());file.close()
func difference(a: PackedFloat32Array,b: PackedFloat32Array) -> float:
    if a.size()!=b.size():return INF
    var error: float=0.
    for i in range(a.size()):error=maxf(error,absf(a[i]-b[i]))
    return error
func run() -> void:
    var lab=load("res://lie_brick_reference_lab.tscn").instantiate();root.add_child(lab);await settle(18)
    if not lab.agent_snapshot().runtime.gpu_ready:
        check(false,"native field and captured renderer initialize: "+lab.failure+" / "+str(lab.effect.failure if lab.effect!=null else "no effect"));lab.queue_free();await settle();quit(1);return
    check(lab.effect.catalog.sha256==lab.manifest.bank_sha256,"shared source identity")
    check(lab.agent_snapshot().metrics.original_mesh_draws==0,"no source mesh draws")
    check(lab.picture!=null and lab.reference_picture!=null and lab.reference_picture.texture!=null,"side by side native UI and real reference texture")
    check(lab.case_control.get_item_metadata(lab.case_control.selected)==lab.state.case,"native controls reflect the validated state")
    for case in lab.manifest.cases:
        check(lab.command({"op":"set_values","values":{"case":case.name,"mode":"total","improved":true,"power":1.0,"radius":false}}).ok,"case command")
        var full: Dictionary=await capture(lab)
        if full.is_empty():break
        check(full.color.size()==int(lab.manifest.resolution)*int(lab.manifest.resolution)*4,"raw linear image shape")
        var positive: bool=false;var finite: bool=true
        for i in range(0,full.color.size(),4):
            for c in range(3):finite=finite and is_finite(full.color[i+c]);positive=positive or full.color[i+c]>.00001
        check(finite and positive,"finite nonblack actual output")
        save(full,case.name+"-lie-total")
        if case.name=="matte_point":root.get_texture().get_image().save_png("res://brick-reference-window.png")
        var row: Dictionary={"device":full.device,"capture_bytes":full.library_bytes,"field_bytes":lab.transport.allocation_bytes,"sample_invocations":full.sample_invocations}
        var serial: int=lab.transport.frame_count;await settle()
        check(lab.transport.frame_count==serial,"idle field reused")
        var decomposition:=PackedFloat32Array();decomposition.resize(full.color.size())
        for mode in ["direct","indirect"]:
            check(lab.command({"op":"set_values","values":{"mode":mode}}).ok,"radiance decomposition command")
            var part: Dictionary=await capture(lab);save(part,case.name+"-lie-"+mode)
            for i in range(0,part.color.size(),4):
                for c in range(3):decomposition[i+c]+=part.color[i+c]
        var error: float=0.
        for i in range(0,full.color.size(),4):
            for c in range(3):error=maxf(error,absf(full.color[i+c]-decomposition[i+c]))
        row["decomposition_max"]=error;check(error<1e-5,"direct plus indirect equals total")
        check(lab.command({"op":"set_values","values":{"mode":"total","improved":false}}).ok,"old transport selection")
        var old: Dictionary=await capture(lab);save(old,case.name+"-lie-legacy")
        check(lab.command({"op":"set_values","values":{"improved":true,"radius":true}}).ok,"radius enabled")
        var bounded: Dictionary=await capture(lab);save(bounded,case.name+"-lie-radius")
        check(lab.command({"op":"set_values","values":{"radius":false}}).ok,"radius restored")
        var restored: Dictionary=await capture(lab);row["policy_restoration_max"]=difference(full.color,restored.color);check(row.policy_restoration_max<1e-6,"policy restoration")
        check(lab.command({"op":"set_values","values":{"power":0.}}).ok,"sources off")
        var dark: Dictionary=await capture(lab);var peak: float=0.
        for i in range(0,dark.color.size(),4):
            for c in range(3):peak=maxf(peak,dark.color[i+c])
        row["off_peak"]=peak;check(peak<1e-7,"no stale ambient")
        check(lab.command({"op":"set_values","values":{"power":1.}}).ok,"sources restored")
        restored=await capture(lab);row["power_restoration_max"]=difference(full.color,restored.color);check(row.power_restoration_max<1e-6,"power restoration")
        var revision: int=lab.revision
        check(not lab.command({"op":"set_values","expected_revision":revision-1,"values":{"power":0.}}).ok and lab.revision==revision,"stale edit rejected")
        check(not lab.command({"op":"set_values","values":{"power":true}}).ok and lab.revision==revision,"boolean power rejected")
        check(not lab.command({"op":"set_values","expected_revision":true,"values":{"power":0.}}).ok and lab.revision==revision,"boolean revision rejected")
        results[case.name]=row
        print("BRICK REFERENCE CASE ",case.name," ",row)
    var file:=FileAccess.open("res://brick-reference-native.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failed":failed,"cases":results,"physical_android_tested":false},"  ",true,true));file.close()
    lab.queue_free();await settle(16);print("BRICK REFERENCE ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
