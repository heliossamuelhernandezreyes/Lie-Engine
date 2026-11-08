extends "res://test_lie_hq_construction.gd"
## The same cases run against the pinned 6.0.1 code and the candidate.
func run() -> void:
    var lab=load("res://lie_hq_construction_lab.tscn").instantiate()
    lab.state.yaw=-32.0682373;lab.state.elevation=-2.1639343;root.add_child(lab);await settle(20)
    var results: Array=[]
    var cases: Array=[{}, {"light":25.}, {"yaw":-23.}, {"normals":false}, {"mode":"opening","yaw":20.,"elevation":22.}, {"mode":"shadow","yaw":15.,"elevation":55.}, {"mode":"corner","yaw":-145.,"elevation":18.,"normals":true}, {"yaw":0.,"elevation":0.}, {"bounces":0,"indirect":false}, {"bounces":2,"indirect":true,"energy_radius":true}]
    var previous: Dictionary={};var geometry_builds: int=0
    for i in range(cases.size()):
        var start: int=Time.get_ticks_usec()
        check(lab.command({"op":"set_values","values":cases[i]}).ok,"probe command")
        var cpu: float=float(Time.get_ticks_usec()-start)/1000.
        var data: Dictionary=await capture(lab)
        check(not data.is_empty() and data.failure.is_empty(),"real native reconstruction")
        if data.is_empty():break
        save(data,"reconstruction-case%d" % i)
        for name in ["color","depth"]:
            var file:=FileAccess.open("res://reconstruction-case%d-%s.f32" % [i,name],FileAccess.WRITE);file.store_buffer(data[name].to_byte_array());file.close()
        var row: Dictionary={"case":i,"state":lab.state.duplicate(),"command_ms":cpu,"profile":data.profile,"samples":data.sample_invocations,"device":data.device,"allocation_bytes":data.allocation_bytes}
        if data.has("pass_counts"):
            row.pass_counts=data.pass_counts.duplicate()
            if i==0:geometry_builds=lab.geometry_builds
            if i==1:
                check(data.depth==previous.depth,"light-only update preserves camera depth")
                check(data.pass_counts.projection_depth==previous.pass_counts.projection_depth and data.pass_counts.material_accumulation==previous.pass_counts.material_accumulation,"light-only update does not dispatch camera rasterization")
            if i==2:
                check(data.shadow==previous.shadow and data.pass_counts.shadow==previous.pass_counts.shadow,"camera-only update preserves resident light visibility")
            if i in [1,2,3]:check(lab.geometry_builds==geometry_builds,"controls reuse immutable CPU geometry")
            if i in [8,9]:check(data.pass_counts.projection_depth==previous.pass_counts.projection_depth and data.pass_counts.shadow==previous.pass_counts.shadow,"field changes preserve both visibility domains")
        results.append(row);previous=data
        print("RECONSTRUCTION PROBE ",i," CPU ",cpu," ms")
    var report: Dictionary={"checks":checks,"failed":failed,"cases":results,"physical_android_tested":false}
    var file:=FileAccess.open("res://construction-reconstruction-native.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
    lab.queue_free();await settle(12);print("CONSTRUCTION RECONSTRUCTION ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
