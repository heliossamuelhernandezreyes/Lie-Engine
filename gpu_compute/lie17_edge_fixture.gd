extends RefCounted
## Production composite against analytic pixel area, flat/feature preservation,
## invalid depth, and a native foreground occluder. No CPU clone of the filter.
const ShaderFile: RDShaderFile=preload("res://shaders/lie17_composite.glsl")
const Helper=preload("res://lie16_temporal_fixture.gd")
const SIDE: int=64

static func _area(normal: Vector2,offset: float,x: int,y: int) -> float:
    var vertices: Array[Vector2]=[Vector2(x,y),Vector2(x+1,y),Vector2(x+1,y+1),Vector2(x,y+1)]
    var clipped: Array[Vector2]=[]
    for i in range(vertices.size()):
        var a: Vector2=vertices[i]
        var b: Vector2=vertices[(i+1)%vertices.size()]
        var da: float=a.dot(normal)-offset
        var db: float=b.dot(normal)-offset
        if da>=0: clipped.append(a)
        if (da>=0)!=(db>=0): clipped.append(a+(b-a)*da/(da-db))
    if clipped.size()<3: return 0
    var area: float=0
    for i in range(clipped.size()): area+=clipped[i].cross(clipped[(i+1)%clipped.size()])
    return absf(area)*.5

static func _texture(rd: RenderingDevice,format_code: int,bytes: PackedByteArray,usage: int) -> RID:
    var format:=RDTextureFormat.new()
    format.width=SIDE; format.height=SIDE; format.format=format_code
    format.usage_bits=usage
    return rd.texture_create(format,RDTextureView.new(),[bytes])

static func run() -> Dictionary:
    var rd: RenderingDevice=RenderingServer.create_local_rendering_device()
    if rd==null: return {"error":"Actual Vulkan device unavailable"}
    var shader: RID=rd.shader_create_from_spirv(ShaderFile.get_spirv())
    var pipeline: RID=rd.compute_pipeline_create(shader)
    var sampler:=RDSamplerState.new()
    sampler.min_filter=RenderingDevice.SAMPLER_FILTER_NEAREST
    sampler.mag_filter=RenderingDevice.SAMPLER_FILTER_NEAREST
    var sampler_rid: RID=rd.sampler_create(sampler)
    var report: Dictionary={}
    var names: Array=["flat","isolated_pixel","thin_line","occluded","mixed_occluder","invalid_depth","transparent","foreground","diagonal_22","diagonal_45","diagonal_68"]
    for name in names:
        var angle: float=deg_to_rad(float(str(name).get_slice("_",1))) if str(name).begins_with("diagonal_") else 0
        var normal:=Vector2(cos(angle),sin(angle))
        var offset: float=normal.dot(Vector2(SIDE*.5+.23,SIDE*.5))
        var source:=PackedFloat32Array()
        var depths:=PackedFloat32Array()
        var native:=PackedFloat32Array()
        var expected:=PackedFloat64Array()
        var background:=PackedFloat32Array()
        for y in range(SIDE):
            for x in range(SIDE):
                var value: float=.4
                var target: float=.4
                if str(name).begins_with("diagonal_"):
                    value=.8 if Vector2(x+.5,y+.5).dot(normal)>=offset else .05
                    target=.05+.75*_area(normal,offset,x,y)
                elif name=="isolated_pixel": value=.8 if x==32 and y==32 else .05; target=value
                elif name=="thin_line": value=.8 if x==32 else .05; target=value
                var z: float=3
                if name=="invalid_depth": z=NAN if x%3==0 else INF if x%3==1 else -1
                var native_z: float=2 if name=="occluded" or (name=="mixed_occluder" and x<SIDE/2) else 4 if name=="foreground" or name=="mixed_occluder" else 0
                if native_z>0 and native_z<z or name in ["invalid_depth","transparent"]: target=.15
                source.append_array(PackedFloat32Array([value,value,value,0 if name=="transparent" else 1]))
                depths.append(z); native.append(1/native_z if native_z>0 else 0)
                expected.append(target)
                background.append_array(PackedFloat32Array([.15,.15,.15,1]))
        var image:=Image.create_from_data(SIDE,SIDE,false,Image.FORMAT_RGBAF,background.to_byte_array())
        image.convert(Image.FORMAT_RGBAH)
        var initial: PackedByteArray=image.get_data()
        var output: RID=_texture(rd,RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,initial,RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT)
        var input: RID=_texture(rd,RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,source.to_byte_array(),RenderingDevice.TEXTURE_USAGE_STORAGE_BIT)
        var native_rid: RID=_texture(rd,RenderingDevice.DATA_FORMAT_R32_SFLOAT,native.to_byte_array(),RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT)
        var depth_rid: RID=rd.storage_buffer_create(depths.size()*4,depths.to_byte_array())
        var depth_uniform:=RDUniform.new()
        depth_uniform.binding=2; depth_uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
        depth_uniform.add_id(sampler_rid); depth_uniform.add_id(native_rid)
        var uniforms: Array[RDUniform]=[Helper._uniform(0,output,true),Helper._uniform(1,input,true),depth_uniform,Helper._uniform(3,depth_rid)]
        var set: RID=rd.uniform_set_create(uniforms,shader,0)
        var metrics: Dictionary={}
        for enabled in [false,true]:
            rd.texture_update(output,0,initial)
            var commands: int=rd.compute_list_begin()
            rd.compute_list_bind_compute_pipeline(commands,pipeline); rd.compute_list_bind_uniform_set(commands,set,0)
            var push: PackedByteArray=PackedInt32Array([SIDE,SIDE,SIDE,SIDE]).to_byte_array()
            push.append_array(PackedFloat32Array([0,-1,1,0]).to_byte_array())
            push.append_array(PackedInt32Array([1,1 if enabled else 0,0,0]).to_byte_array())
            rd.compute_list_set_push_constant(commands,push,48)
            rd.compute_list_dispatch(commands,SIDE/8,SIDE/8,1)
            rd.compute_list_end(); rd.submit(); rd.sync()
            var result:=Image.create_from_data(SIDE,SIDE,false,Image.FORMAT_RGBAH,rd.texture_get_data(output,0))
            result.convert(Image.FORMAT_RGBAF)
            var colors: PackedFloat32Array=result.get_data().to_float32_array()
            var sum: float=0
            var maximum: float=0
            var count: int=0
            for y in range(3,SIDE-3):
                for x in range(3,SIDE-3):
                    var index: int=y*SIDE+x
                    var error: float=absf(colors[index*4]-expected[index])
                    sum+=error*error; maximum=maxf(maximum,error); count+=1
            metrics["enabled" if enabled else "disabled"]={"rmse":sqrt(sum/count),"maximum_error":maximum}
            if str(name).begins_with("diagonal_"):
                result.convert(Image.FORMAT_RGBA8)
                result.save_png("res://lie17-fixture-"+str(name)+("-on" if enabled else "-off")+".png")
        report[name]=metrics
        rd.free_rid(set)
        for rid in [output,input,native_rid,depth_rid]: rd.free_rid(rid)
    rd.free_rid(pipeline); rd.free_rid(shader); rd.free_rid(sampler_rid); rd.free()
    return report
