extends "res://test_lie_wall07_mobile.gd"
## Actual reconstruction shader: 220k source reference vs equal-budget subsets.
const SourceShader=preload("res://shaders/lie_wall10_source.glsl")
const Model=preload("res://lie11_model.gd")
const SIZE: int=256
var rd: RenderingDevice
var shader: RID
var pipeline: RID
var bank: RID
func u(binding: int,rid: RID,image: bool=false) -> RDUniform:
    var out:=RDUniform.new();out.binding=binding;out.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if image else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;out.add_id(rid);return out
func draw(lab,source_ids: PackedByteArray,radius: float,angle: float,irradiance: PackedFloat32Array) -> Dictionary:
    var count: int=source_ids.size()/4;var params: PackedByteArray=lab.effect._pending["parameters"].duplicate()
    var instance: PackedByteArray=lab.effect._pending["instances"].slice(42*96,43*96);instance.encode_float(72,radius)
    var center:=Vector3(instance.decode_float(48),instance.decode_float(52),instance.decode_float(56))
    var eye: Vector3=center+Vector3(sin(deg_to_rad(angle))*.30,.02,cos(deg_to_rad(angle))*.30);var forward: Vector3=(center-eye).normalized();var right: Vector3=forward.cross(Vector3.UP).normalized();var up: Vector3=right.cross(forward)
    var basis: Array=[eye,right,up,forward]
    for i in range(4):
        for k in range(3):params.encode_float(i*16+k*4,basis[i][k])
    params.encode_float(64,.65);params.encode_float(72,.005);params.encode_float(76,10.)
    for pair in [[80,count],[84,1],[88,SIZE],[92,SIZE]]:params.encode_s32(pair[0],pair[1])
    var data: Dictionary={1:instance,2:PackedInt32Array([0,count,0,0]).to_byte_array(),6:params,15:Model.patch_bytes(lab.light_model),16:lab.effect._joint_layout_bytes(),17:source_ids,21:lab.effect._groups}
    for pair in [[3,count*96],[4,SIZE*SIZE*4],[5,SIZE*SIZE*4],[7,SIZE*SIZE*32],[13,512*512*4],[18,SIZE*SIZE*4],[19,160],[20,16],[22,32],[23,272],[24,32],[25,32],[26,16],[27,16],[28,count*8]]:
        var bytes:=PackedByteArray();bytes.resize(pair[1]);data[pair[0]]=bytes
    var rids: Dictionary={0:bank};var uniforms: Array[RDUniform]=[u(0,bank)]
    for binding in data:rids[binding]=rd.storage_buffer_create(data[binding].size(),data[binding]);uniforms.append(u(binding,rids[binding]))
    var images: Dictionary={}
    for binding in [8,9,11,12,14]:
        var format:=RDTextureFormat.new();format.width=872 if binding==14 else SIZE;format.height=1 if binding==14 else SIZE;format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
        format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
        images[binding]=rd.texture_create(format,RDTextureView.new(),[irradiance.to_byte_array()] if binding==14 else []);uniforms.append(u(binding,images[binding],true))
    var set_rid: RID=rd.uniform_set_create(uniforms,shader,0);check(set_rid.is_valid(),"reference source shader uniform set")
    var list: int=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set_rid,0)
    for stage in [1,2,3,4,6]:
        var threads: int=maxi(SIZE*SIZE,512*512) if stage==1 else count if stage in [2,3] else SIZE*SIZE
        rd.compute_list_set_push_constant(list,PackedInt32Array([stage,1,0,0]).to_byte_array(),16);rd.compute_list_dispatch(list,ceili(float(threads)/64.),1,1);rd.compute_list_add_barrier(list)
    rd.compute_list_end();rd.submit();rd.sync()
    var result: Dictionary={"color":rd.texture_get_data(images[11],0).to_float32_array(),"depth":rd.buffer_get_data(rids[4]).to_float32_array(),"winner":rd.buffer_get_data(rids[5]).to_int32_array(),"accumulator":rd.buffer_get_data(rids[7]).to_int32_array()}
    rd.free_rid(set_rid)
    for rid in images.values():rd.free_rid(rid)
    for binding in rids:
        if binding!=0:rd.free_rid(rids[binding])
    return result
func metrics(reference: Dictionary,candidate: Dictionary) -> Dictionary:
    var missing: int=0;var extra: int=0;var common: int=0;var depth: float=0.;var rgb: float=0.
    for i in range(SIZE*SIZE):
        var a: bool=reference["winner"][i]>=0;var b: bool=candidate["winner"][i]>=0
        if a and not b:missing+=1
        if b and not a:extra+=1
        if a and b:
            common+=1;depth+=absf(reference["depth"][i]-candidate["depth"][i])
            for k in range(3):
                var aa: float=float(reference["accumulator"][i*8+k])/maxf(float(reference["accumulator"][i*8+3]),1.)
                var bb: float=float(candidate["accumulator"][i*8+k])/maxf(float(candidate["accumulator"][i*8+3]),1.)
                rgb+=absf(aa-bb)
    return {"missing_source_pixels":missing,"extra_pixels":extra,"common_pixels":common,"depth_mae_m":depth/maxf(common,1.),"linear_albedo_mae":rgb/maxf(common*3,1.)}
func save_piece(data: Dictionary,name: String) -> void:
    var color: PackedFloat32Array=data["color"].duplicate()
    for i in range(0,color.size(),4):
        var rgb:=Color(color[i]*2.,color[i+1]*2.,color[i+2]*2.).linear_to_srgb();color[i]=rgb.r;color[i+1]=rgb.g;color[i+2]=rgb.b
    var image:=Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_RGBAF,color.to_byte_array());image.convert(Image.FORMAT_RGBA8);image.save_png("res://source-piece-"+name+".png")
func run() -> void:
    var lab=load("res://lie_wall10_android_lab.tscn").instantiate();root.add_child(lab);await settle(16)
    if not lab.effect.gpu_ready:printerr(lab.effect.failure);quit(1);return
    var transport: Dictionary=await capture(lab.transport)
    rd=RenderingServer.create_local_rendering_device();shader=rd.shader_create_from_spirv(SourceShader.get_spirv());pipeline=rd.compute_pipeline_create(shader);bank=rd.storage_buffer_create(lab.effect._samples.size(),lab.effect._samples)
    var dense:=PackedInt32Array()
    for i in range(220000):dense.append(i)
    var job: Array=lab.effect.catalog["wall05"]["instance_jobs"][0][42];var start: int=int(job[0])*4;var finish: int=start+int(job[1])*4
    var legacy: PackedByteArray=lab.effect._legacy_references.slice(start,finish);var selected: PackedByteArray=lab.effect._source_packets["references"].slice(start,finish)
    var cases: Dictionary={}
    for angle in [0.,35.,60.]:
        var reference: Dictionary=draw(lab,dense.to_byte_array(),0.,angle,transport["irradiance"])
        var before: Dictionary=draw(lab,legacy,.0052,angle,transport["irradiance"]);var after: Dictionary=draw(lab,selected,.0052,angle,transport["irradiance"])
        var a: Dictionary=metrics(reference,before);var b: Dictionary=metrics(reference,after);cases[str(angle)]={"legacy":a,"selected":b}
        check(a["common_pixels"]>1000 and b["common_pixels"]>1000,"real dense reference has visible source support")
        check(b["depth_mae_m"]<.01 and b["linear_albedo_mae"]<.12,"bounded source depth and material error")
        save_piece(reference,str(int(angle))+"-dense");save_piece(before,str(int(angle))+"-legacy");save_piece(after,str(int(angle))+"-selected")
    var file:=FileAccess.open("res://source-piece-native.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"device":rd.get_device_name(),"reference":"220000 genuine captured source IDs at original radii; same actual GPU kernel; no hole recovery","cases":cases,"physical_android_tested":false},"  ",true,true));file.close()
    rd.free_rid(bank);rd.free_rid(pipeline);rd.free_rid(shader);rd.free();lab.queue_free();await settle();print("SOURCE PIECE ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
