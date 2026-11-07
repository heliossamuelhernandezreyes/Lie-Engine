extends SceneTree
var checks: int=0
var failed: bool=false
var rows: Dictionary={}
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("HQ FAIL ",label)
func settle(n: int=6) -> void:
    for i in range(n):await process_frame
func capture(lab: Node) -> Dictionary:
    await settle();lab.effect.request_readback()
    for i in range(240):
        await process_frame
        var data: Dictionary=lab.effect.readback()
        if not data.is_empty():return data
    check(false,"readback");return {}
func save(data: Dictionary,name: String,raw: bool=false) -> void:
    var image:=Image.create_from_data(data.output_size,data.output_size,false,Image.FORMAT_RGBAF,data.color.to_byte_array());image.convert(Image.FORMAT_RGBA8);image.save_png("res://"+name+".png")
    if raw:
        var f:=FileAccess.open("res://"+name+".rgba32f",FileAccess.WRITE);f.store_buffer(data.color.to_byte_array());f.close()
        f=FileAccess.open("res://"+name+".depth32f",FileAccess.WRITE);f.store_buffer(data.depth.to_byte_array());f.close()
func difference(a: PackedFloat32Array,b: PackedFloat32Array) -> float:
    var peak: float=0
    for i in range(a.size()):peak=maxf(peak,absf(a[i]-b[i]))
    return peak
func run() -> void:
    var lab=load("res://lie_hq_material_lab.tscn").instantiate();root.add_child(lab);await settle(20)
    for material in lab.MATERIALS:
        check(lab.command({"op":"set_values","values":{"material":material,"yaw":0.,"elevation":0.,"light":-35.,"zoom":1.,"lod":0,"assembly":false}}).ok,"material command")
        var front: Dictionary=await capture(lab)
        check(lab.effect.gpu_ready and lab.metrics.get("configured",false),"actual GPU bank: "+lab.effect.failure)
        if front.is_empty():continue
        save(front,material+"-front",true)
        var coverage: int=0;var finite: bool=true
        for i in range(0,front.color.size(),4):
            if front.color[i+3]>.99:coverage+=1
            for c in range(4):finite=finite and is_finite(front.color[i+c])
        check(finite and coverage>400000,"finite high-resolution surface coverage")
        check(front.output_size==1024 and front.library_bytes==53760000,"1024 capture and bounded immutable bank")
        check(front.asset_uploads==1 and front.sample_bank_bindings==1 and lab.metrics.source_mesh_draws==0,"captured samples only, one immutable bank")
        for pose in [{"yaw":40.,"elevation":25.},{"yaw":-40.,"elevation":-20.},{"yaw":0.,"elevation":0.,"light":55.},{"lod":1},{"lod":2},{"lod":0,"assembly":true}]:
            check(lab.command({"op":"set_values","values":pose}).ok,"calibrated pose/LOD/set command")
            var data: Dictionary=await capture(lab);save(data,material+"-case-"+str(rows.size()))
            check(not data.is_empty() and data.asset_uploads==1,"views and sets reuse source bank")
            if pose.has("light"):check(difference(front.color,data.color)>.01,"runtime relighting changes captured output")
            rows[material+"-case-"+str(rows.size())]={"state":lab.state.duplicate(),"instances":data.instances,"samples":data.sample_invocations}
        lab.command({"op":"set_values","values":{"yaw":0.,"elevation":0.,"light":-35.,"lod":0,"assembly":false}})
        var restored: Dictionary=await capture(lab);check(difference(front.color,restored.color)<1e-6,"deterministic restore")
        var second=load("res://lie_hq_material_effect.gd").new(material,1024);var pending: Dictionary=lab.effect._pending.duplicate(true)
        check(second.configure(pending.parameters,pending.instances,pending.jobs,pending.work),"second consumer configure")
        lab.world_environment.compositor.compositor_effects=[lab.effect,second];await settle(16);second.request_readback();await settle(12)
        var shared: Dictionary=second.readback();check(not shared.is_empty() and shared.get("asset_uploads",-1)==0,"second consumer borrows exact bank")
        lab.world_environment.compositor.compositor_effects=[lab.effect];second.shutdown();second=null;await settle(12)
        check(not (await capture(lab)).is_empty(),"consumer survives shared release")
        rows[material]={"device":front.device,"coverage_pixels":coverage,"state":lab.state.duplicate(),"source_triangles":lab.effect.catalog.source_original_triangles,"bank_sha256":lab.effect.catalog.sha256,"physical_android_tested":false}
    var rev: int=lab.revision
    for values in [{"material":"missing"},{"zoom":true},{"yaw":NAN},{"lod":true},{"assembly":1}]:check(not lab.command({"op":"set_values","values":values}).ok and lab.revision==rev,"invalid command atomic")
    check(not lab.command({"op":"set_values","expected_revision":rev-1,"values":{"lod":0}}).ok,"stale revision rejected")
    var f:=FileAccess.open("res://hq-native.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failed":failed,"cases":rows},"  "));f.close()
    lab.queue_free();await settle(16);print("HQ MATERIALS ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
