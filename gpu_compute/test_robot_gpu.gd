extends SceneTree
const Lab=preload("res://lie_robot_lab.gd")
const Assembly=preload("res://lie_robot_assembly.gd")
var lab: Node3D
var checks: int=0
var failed: bool=false
var max_position_error: float=0
var max_normal_error: float=0
func _initialize() -> void:call_deferred("run")
func expect(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;push_error("ROBOT GPU: "+label)
func settle() -> void:
    for i in range(5):await process_frame
func read() -> Dictionary:
    lab.effect.request_readback()
    for i in range(120):
        await process_frame;var data: Dictionary=lab.effect.readback()
        if data.has("probes"):return data
    return {}
func meshes(node: Node) -> int:
    var count: int=1 if node is MeshInstance3D else 0
    for child in node.get_children():count+=meshes(child)
    return count
func verify(data: Dictionary) -> void:
    expect(not data.is_empty(),"Actual rendering-device readback")
    if data.is_empty():return
    var source: PackedFloat32Array=FileAccess.get_file_as_bytes("res://captures/robot_modular/library.bin").to_float32_array();var objects: PackedFloat32Array=data["instance_packet"];var curves: PackedFloat32Array=data["curve_packet"]
    for p in data["probes"]:
        var s: int=p["sample"]*24;var i: int=p["instance"]*24;var local:=Vector3(source[s],source[s+1],source[s+2]);var normal:=Vector3(source[s+4],source[s+5],source[s+6]);var shade:=Vector3(source[s+20],source[s+21],source[s+22])
        var position: Vector3;var basis: Basis
        if objects[i+17]>=0:
            position=Assembly.cable_position(local,curves,int(objects[i+17]),objects[i+18]);basis=Assembly.cable_jacobian(local,curves,int(objects[i+17]),objects[i+18])
        else:
            basis=Basis(Vector3(objects[i],objects[i+1],objects[i+2]),Vector3(objects[i+4],objects[i+5],objects[i+6]),Vector3(objects[i+8],objects[i+9],objects[i+10]));position=basis*local+Vector3(objects[i+12],objects[i+13],objects[i+14])
        var error: float=position.distance_to(Vector3(p["position"][0],p["position"][1],p["position"][2]));max_position_error=maxf(max_position_error,error);expect(error<.0003,"Captured sample follows CPU pose/curve oracle")
        var transform: Basis=basis.inverse().transposed();var expected: Vector3=(transform*normal).normalized();var actual:=Vector3(p["geometric_normal"][0],p["geometric_normal"][1],p["geometric_normal"][2]);var nerror: float=expected.distance_to(actual);max_normal_error=maxf(max_normal_error,nerror);expect(nerror<.015,"Inverse-Jacobian geometric normal")
        expected=(transform*shade).normalized();actual=Vector3(p["shading_normal"][0],p["shading_normal"][1],p["shading_normal"][2]);expect(expected.distance_to(actual)<.015,"Captured shading normal remains independent")
    expect(data["asset_uploads"]==1 and data["sample_invocations"]<=750000,"Resident bank and work budget")
    var colors: PackedFloat32Array=data["color"];var owned: int=0;var finite: bool=true
    for i in range(0,colors.size(),4):
        if colors[i+3]>.5:owned+=1
        finite=finite and is_finite(colors[i]) and is_finite(colors[i+1]) and is_finite(colors[i+2])
    expect(finite,"All shaded pixels finite")
    expect(owned>1000,"Nonempty robot output")
func run() -> void:
    lab=Lab.new();root.add_child(lab);await settle();expect(lab.effect.capture_loaded and lab.effect.gpu_ready,"Vulkan robot initialized");expect(meshes(lab)==0,"No original/source meshes drawn")
    var base: Dictionary=await read();verify(base)
    # Detect the ground holes seen in the first visual pass using independent rays.
    var size: int=base["output_size"];var pixels: PackedFloat32Array=base["color"];var floor_checked: int=0;var missing: int=0;var camera: Camera3D=lab.camera
    for y in range(0,size,12):
        for x in range(0,size,12):
            var uv: Vector2=(Vector2(x,y)+Vector2(.5,.5))/size;var tangent: float=tan(deg_to_rad(camera.fov)*.5);var ray: Vector3=-camera.basis.z+camera.basis.x*((2*uv.x-1)*tangent)+camera.basis.y*((1-2*uv.y)*tangent)
            if ray.y>=-.0001:continue
            var point: Vector3=camera.position+ray*(-camera.position.y/ray.y)
            if absf(point.x)>1.35 or absf(point.z)>1.35:continue
            floor_checked+=1
            if pixels[(y*size+x)*4+3]<.90:missing+=1
    expect(floor_checked>20 and missing==0,"Ground has continuous interior coverage")
    expect(lab.command({"op":"set_values","values":{"focus":"arm","pose":{"right_elbow":105,"right_shoulder":35},"grip":.8}})["ok"],"Native articulation command")
    await settle();var posed: Dictionary=await read();verify(posed)
    expect(lab.command({"op":"set_values","values":{"focus":"body","mode":"walk","time":.25}})["ok"],"Native walk command")
    await settle();verify(await read())
    expect(lab.command({"op":"set_values","values":{"focus":"head","mode":"manual","unlit":true}})["ok"],"Albedo inspection command")
    await settle();verify(await read())
    var report: Dictionary={"checks":checks,"failed":failed,"max_position_error_m":max_position_error,"max_geometric_normal_error":max_normal_error,"floor_checked_pixels":floor_checked,"floor_missing_pixels":missing,"device":base.get("device",""),"note":"Actual software Vulkan; no physical GPU performance claim."}
    var file:=FileAccess.open("res://robot-gpu-verification.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close();print("ROBOT GPU ",JSON.stringify(report));root.remove_child(lab);lab.free();await process_frame;quit(1 if failed else 0)
