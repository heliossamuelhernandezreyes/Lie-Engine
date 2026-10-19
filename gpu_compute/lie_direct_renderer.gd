extends RefCounted
## Opaque layered surface consumer. All RIDs here are owned except transport
## inputs and the two caller-owned output images. No source/visibility SSBOs.
const SurfaceShader = preload("res://shaders/lie_direct_surface.glsl")
const ShadowShader = preload("res://shaders/lie_direct_shadow.glsl")
const LightShader = preload("res://shaders/lie_direct_light_built.glsl")
const RegionsShader = preload("res://shaders/lie_direct_regions.glsl")
const RegionsShadowShader = preload("res://shaders/lie_direct_regions_shadow.glsl")
const EnvelopeShader = preload("res://shaders/lie_direct_envelope.glsl")
const EnvelopeShadowShader = preload("res://shaders/lie_direct_envelope_shadow.glsl")
const SHADOW_SIZE: int = 512
var failure: String = ""
var proof: Dictionary = {}
var access_proof: Dictionary = {}
var _draw_sets: Dictionary = {}
var _backend: String = ""
var requested_bytes: int = 0
var primary_builds: int = 0
var shadow_builds: int = 0
var shadow_light_builds: int = 0
var node_builds: int = 0
var shade_builds: int = 0
var _rd: RenderingDevice
var _textures: Array[RID] = []
var _buffers: Array[RID] = []
var _frames: Array[RID] = []
var _sets: Array[RID] = []
var _programs: Dictionary = {}
var _sampler := RID()
var _world := RID()
var _normal := RID()
var _color := RID()
var _shadows := RID()
var _views := RID()
var _options := RID()
var _nodes := RID()
var _light_set := RID()
var _surface_set := RID()
var _shadow_set := RID()
var _primary_frame := RID()
var _shadow_frames: Array[RID] = []
var _size: int = 0
var _lights: int = 0
var _transport_serial: int = -1
var _camera_key := PackedByteArray()
var _primary_depth := RID()
var _shadow_keys: Array[PackedByteArray] = []
var _proxy_packet := PackedByteArray()
var _view_packet := PackedByteArray()

func _uniform(binding: int, rid: RID, kind: int = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER) -> RDUniform:
    var u := RDUniform.new(); u.binding = binding; u.uniform_type = kind
    if kind == RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE: u.add_id(_sampler)
    u.add_id(rid); return u

func _buffer(data: PackedByteArray) -> RID:
    var rid: RID = _rd.storage_buffer_create(data.size(), data)
    _buffers.append(rid); requested_bytes += data.size(); return rid

func _texture(format: int, width: int, height: int, usage: int, layers: int = 1, data: Array[PackedByteArray] = []) -> RID:
    if not _rd.texture_is_format_supported_for_usage(format, usage):
        failure = "Unsupported native surface attachment: " + str(format); return RID()
    var f := RDTextureFormat.new(); f.format = format; f.width = width; f.height = height; f.usage_bits = usage
    if layers > 1: f.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY; f.array_layers = layers
    var rid: RID = _rd.texture_create(f, RDTextureView.new(), data)
    _textures.append(rid)
    requested_bytes += width * height * layers * (16 if format == RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT else 8 if format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else 4)
    if not rid.is_valid(): failure = "Native surface texture allocation"
    return rid

func _matrix(packet: PackedFloat32Array, pose: Transform3D) -> void:
    for v in [pose.basis.x, pose.basis.y, pose.basis.z]:
        packet.append_array(PackedFloat32Array([v.x, v.y, v.z, 0.]))
    packet.append_array(PackedFloat32Array([pose.origin.x,pose.origin.y,pose.origin.z,1.]))

func _proxies(catalog: Dictionary) -> PackedByteArray:
    var packet := PackedByteArray()
    var dims: Array = catalog["wall06"]["aligned_bbox_m"]
    var scale := Vector3((float(dims[0]) + .0055) / float(dims[0]), (float(dims[1]) + .0055) / float(dims[1]), 1.)
    for index in range(97):
        var pose := Transform3D.IDENTITY; var tone: float = 1.
        if index < 96:
            var authored: Dictionary = catalog["wall05"]["poses"][index]; var p: Array = authored["center"]
            pose = Transform3D(Basis(Vector3.UP, float(authored["yaw_rad"])).scaled(scale), Vector3(p[0],p[1],p[2])); tone = authored["tone"]
        var box: Dictionary = proof["boxes"][0 if index < 96 else 1]
        var floats := PackedFloat32Array(); _matrix(floats, pose); _matrix(floats, pose.affine_inverse())
        for key in ["lo", "hi"]:
            var p: Array = box[key]; floats.append_array(PackedFloat32Array([p[0],p[1],p[2],0]))
        floats.append_array(PackedFloat32Array([tone,0,index*9 if index<96 else 0,0])); packet.append_array(floats.to_byte_array())
        packet.append_array(PackedInt32Array([int(box["first_face"]),0,0,0]).to_byte_array())
    return packet

func initialize(rd: RenderingDevice, catalog: Dictionary, size: int, transport: CompositorEffect, output: RID, light_groups: RID) -> bool:
    _rd = rd; _size = size; _lights = transport.desired_light_count
    if _lights < 1 or _lights > 8: failure = "Native field requires 1..8 published lights"; return false
    var root: String = "res://captures/liewall06/direct/"
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(root + "surface.json"))
    if not parsed is Dictionary or parsed.get("schema") != "lie-layered-surface/1" or parsed.get("source_bank_sha256") != catalog["sha256"]:
        failure = "Missing or incompatible compiled captured surface"; return false
    proof = parsed
    var access: Variant = JSON.parse_string(FileAccess.get_file_as_string(root + "access.json"))
    if not access is Dictionary or access.get("schema") != "lie-surface-access/1" or access.get("source_bank_sha256") != proof["source_bank_sha256"] or access.get("source_packets") != proof["packets"]:
        failure = "Missing or incompatible compiled access alternatives"; return false
    access_proof = access
    for name in access_proof["packets"]:
        if FileAccess.get_sha256(root + name) != access_proof["packets"][name]["sha256"] or FileAccess.get_file_as_bytes(root + name).size() != int(access_proof["packets"][name]["bytes"]):
            failure = "Access packet identity: " + name; return false
    var atlas: Dictionary = {}; var sample_usage: int = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
    for name in ["depth", "normal", "color"]:
        var path: String = root + name + ".bin"; var declaration: Dictionary = proof["packets"][name + ".bin"]
        if FileAccess.get_sha256(path) != declaration["sha256"]: failure = "Compiled surface SHA: " + name; return false
        var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
        if bytes.size() != int(declaration["bytes"]): failure = "Compiled surface length"; return false
        var layers: int = 1 if name == "depth" else 4; var chunks: Array[PackedByteArray] = []
        var stride: int = bytes.size() / layers
        for layer in range(layers): chunks.append(bytes.slice(layer*stride, (layer+1)*stride))
        atlas[name] = _texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT if name == "depth" else RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, int(proof["width"]), int(proof["height"]), sample_usage, layers, chunks)
        if not atlas[name].is_valid(): return false
    var state := RDSamplerState.new(); state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST; state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
    _sampler = _rd.sampler_create(state)
    _proxy_packet = _proxies(catalog); var proxies: RID = _buffer(_proxy_packet)
    var rects := PackedInt32Array()
    for face in proof["faces"]: rects.append_array(PackedInt32Array([face["x"],face["y"],face["width"],face["height"]]))
    var rectangles: RID = _buffer(rects.to_byte_array())
    var region_texture: RID = _texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,int(access_proof["region_width"]),int(access_proof["region_height"]),sample_usage,1,[FileAccess.get_file_as_bytes(root + "regions.bin")])
    var region_rects := PackedInt32Array()
    for rect in access_proof["region_rects"]:
        for value in rect: region_rects.append(int(value))
    var region_rectangles: RID = _buffer(region_rects.to_byte_array())
    var envelope: RID = _buffer(FileAccess.get_file_as_bytes(root + "envelope.bin"))
    _view_packet.resize((1+6*_lights)*80); _views = _buffer(_view_packet)
    var options := PackedByteArray(); options.resize(32); _options = _buffer(options)
    var node_data := PackedByteArray(); node_data.resize(1024*(1+_lights)*16); _nodes = _buffer(node_data)
    var color_usage: int = sample_usage | RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT
    var depth_usage: int = sample_usage | RenderingDevice.TEXTURE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
    _world = _texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,size,size,color_usage)
    _normal = _texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,size,size,color_usage)
    _color = _texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,size,size,color_usage)
    var depth: RID = _texture(RenderingDevice.DATA_FORMAT_D32_SFLOAT,size,size,depth_usage)
    _primary_depth = depth
    _shadows = _texture(RenderingDevice.DATA_FORMAT_D32_SFLOAT,SHADOW_SIZE,SHADOW_SIZE,depth_usage,_lights*6)
    if failure != "": return false
    _primary_frame = _rd.framebuffer_create([_world,_normal,_color,depth]); _frames.append(_primary_frame)
    for layer in range(_lights*6):
        var slice: RID = _rd.texture_create_shared_from_slice(RDTextureView.new(),_shadows,layer,0)
        var frame: RID = _rd.framebuffer_create([slice]); _frames.append(frame); _shadow_frames.append(frame)
    var files: Dictionary = {"surface":SurfaceShader,"shadow":ShadowShader,"regions":RegionsShader,"regions_shadow":RegionsShadowShader,"envelope":EnvelopeShader,"envelope_shadow":EnvelopeShadowShader,"light":LightShader}
    for key in files:
        var file: RDShaderFile = files[key]
        var spirv: RDShaderSPIRV = file.get_spirv()
        for stage in [RenderingDevice.SHADER_STAGE_COMPUTE,RenderingDevice.SHADER_STAGE_VERTEX,RenderingDevice.SHADER_STAGE_FRAGMENT]:
            if spirv.get_stage_compile_error(stage) != "": failure = spirv.get_stage_compile_error(stage); return false
        var shader: RID = _rd.shader_create_from_spirv(spirv); var pipeline: RID
        if key == "light": pipeline = _rd.compute_pipeline_create(shader)
        else:
            var raster := RDPipelineRasterizationState.new(); raster.cull_mode = RenderingDevice.POLYGON_CULL_DISABLED
            var depth_state := RDPipelineDepthStencilState.new(); depth_state.enable_depth_test = true; depth_state.enable_depth_write = true; depth_state.depth_compare_operator = RenderingDevice.COMPARE_OP_LESS
            var blend := RDPipelineColorBlendState.new(); var attachments: Array[RDPipelineColorBlendStateAttachment] = []
            if key in ["surface","regions","envelope"]:
                for i in range(3): attachments.append(RDPipelineColorBlendStateAttachment.new())
            blend.attachments = attachments
            pipeline = _rd.render_pipeline_create(shader,_rd.framebuffer_get_format(_primary_frame if key in ["surface","regions","envelope"] else _shadow_frames[0]),-1,RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,raster,RDPipelineMultisampleState.new(),depth_state,blend)
        _programs[key] = {"shader":shader,"pipeline":pipeline}
        if not pipeline.is_valid(): failure = "Native opaque pipeline: " + key; return false
    var uniforms: Array[RDUniform] = [_uniform(0,proxies),_uniform(1,_views),_uniform(2,atlas["depth"],RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE),_uniform(3,atlas["normal"],RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE),_uniform(4,atlas["color"],RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE),_uniform(5,rectangles)]
    _surface_set = _rd.uniform_set_create(uniforms,_programs["surface"]["shader"],0); _sets.append(_surface_set)
    # The shader ABI retains the surface samplers, including depth-only passes.
    var shadow_uniforms: Array[RDUniform] = uniforms
    _shadow_set = _rd.uniform_set_create(shadow_uniforms,_programs["shadow"]["shader"],0); _sets.append(_shadow_set)
    _draw_sets = {"surface":_surface_set,"shadow":_shadow_set}
    for key in ["regions","regions_shadow","envelope","envelope_shadow"]:
        var extra: Array[RDUniform] = uniforms.duplicate()
        if key.begins_with("regions"):
            extra.append(_uniform(6,region_texture,RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE)); extra.append(_uniform(7,region_rectangles))
        else: extra.append(_uniform(8,envelope))
        var set: RID = _rd.uniform_set_create(extra,_programs[key]["shader"],0)
        if not set.is_valid(): failure = "Access descriptors: " + key; return false
        _draw_sets[key] = set; _sets.append(set)
    var group_buffer: RID = light_groups
    var light_uniforms: Array[RDUniform] = [_uniform(0,_world,RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE),_uniform(1,_normal,RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE),_uniform(2,_color,RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE),_uniform(3,_shadows,RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE),_uniform(4,output,RenderingDevice.UNIFORM_TYPE_IMAGE),_uniform(5,transport.output_rid,RenderingDevice.UNIFORM_TYPE_IMAGE),_uniform(6,transport.material_codes_rid()),_uniform(7,transport.surface_light_codes_rid()),_uniform(8,group_buffer),_uniform(9,_views),_uniform(10,_nodes),_uniform(11,transport.emission_descriptors_rid()),_uniform(12,_options)]
    _light_set = _rd.uniform_set_create(light_uniforms,_programs["light"]["shader"],0); _sets.append(_light_set)
    var ready: bool = _surface_set.is_valid() and _shadow_set.is_valid() and _light_set.is_valid()
    if not ready: failure = "Native surface descriptors"
    return ready

func _view(at: int, eye: Vector3, right: Vector3, up: Vector3, forward: Vector3, tangent: float) -> void:
    var values := PackedFloat32Array()
    for v in [eye,right,up,forward]: values.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    values.append_array(PackedFloat32Array([.001,40.,tangent,0])); var bytes: PackedByteArray = values.to_byte_array()
    for i in range(80): _view_packet[at*80+i] = bytes[i]

func _draw(key: String, frame: RID, view: int) -> void:
    var clear: PackedColorArray = [Color(0,0,0,0),Color(0,0,0,0),Color(0,0,0,0)] if key in ["surface","regions","envelope"] else []
    var list: int = _rd.draw_list_begin(frame,RenderingDevice.DRAW_CLEAR_ALL,clear,1.)
    _rd.draw_list_bind_render_pipeline(list,_programs[key]["pipeline"])
    _rd.draw_list_bind_uniform_set(list,_draw_sets[key],0)
    if key.begins_with("envelope"):
        for master in range(2):
            var group: Dictionary = access_proof["envelope_groups"][master]
            _rd.draw_list_set_push_constant(list,PackedInt32Array([view,int(group["first_quad"]),0 if master==0 else 96,0]).to_byte_array(),16)
            _rd.draw_list_draw(list,false,96 if master==0 else 1,int(group["quads"])*6)
    else:
        _rd.draw_list_set_push_constant(list,PackedInt32Array([view,0,0,0]).to_byte_array(),16)
        _rd.draw_list_draw(list,false,97,36)
    _rd.draw_list_end()

func _stamp(profile: RefCounted, owner: int, serial: int, name: String, edge: String) -> void:
    if profile != null: _rd.capture_timestamp(profile.marker(owner,serial,name,edge))

func render(parameters: PackedByteArray, transport: CompositorEffect, shadows: bool, material: bool, force: bool = false, backend: String = "surface", profile: RefCounted = null, owner: int = 0, serial: int = 0) -> Dictionary:
    if backend != _backend: invalidate(); _backend = backend
    var floats: PackedFloat32Array = parameters.to_float32_array()
    var camera_key: PackedByteArray = parameters.slice(0,96)
    var primary_dirty: bool = force or camera_key != _camera_key
    _view(0,Vector3(floats[0],floats[1],floats[2]),Vector3(floats[4],floats[5],floats[6]),Vector3(floats[8],floats[9],floats[10]),Vector3(floats[12],floats[13],floats[14]),floats[16])
    var inputs: Dictionary = transport.direct_response_inputs(); var lights: PackedByteArray = inputs["lights"]
    var changed_lights: Array[int] = []
    if _shadow_keys.is_empty(): _shadow_keys.resize(_lights)
    var directions: Array[Vector3] = [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]
    for l in range(_lights):
        var at: int = l*32; var eye := Vector3(lights.decode_float(at),lights.decode_float(at+4),lights.decode_float(at+8))
        var key: PackedByteArray = lights.slice(at,at+16)
        if shadows and (force or key != _shadow_keys[l]): changed_lights.append(l); _shadow_keys[l] = key
        for face in range(6):
            var forward: Vector3 = directions[face]; var up: Vector3 = Vector3.FORWARD if face==2 else Vector3.BACK if face==3 else Vector3.UP
            var right: Vector3 = forward.cross(up).normalized(); up = right.cross(forward).normalized()
            _view(1+l*6+face,eye,right,up,forward,1.)
    var shadow_dirty: bool = not changed_lights.is_empty()
    _rd.buffer_update(_views,0,_view_packet.size(),_view_packet)
    var options: PackedByteArray = PackedInt32Array([1 if shadows else 0,1 if material else 0,0,0]).to_byte_array()
    options.append_array(PackedFloat32Array([.0005,.0004,0,0]).to_byte_array()); _rd.buffer_update(_options,0,32,options)
    if primary_dirty:
        _stamp(profile,owner,serial,"primary","begin")
        _draw(backend,_primary_frame,0); primary_builds += 1; _camera_key = camera_key
        _stamp(profile,owner,serial,"primary","end")
    if shadow_dirty:
        _stamp(profile,owner,serial,"shadow_maps","begin")
        for light in changed_lights:
            for face in range(6):
                var index: int = light*6+face; _draw("shadow" if backend=="surface" else backend+"_shadow",_shadow_frames[index],1+index)
        shadow_builds += 1; shadow_light_builds += changed_lights.size()
        _stamp(profile,owner,serial,"shadow_maps","end")
    if transport.frame_count != _transport_serial or force:
        _stamp(profile,owner,serial,"node_response","begin")
        var list: int = _rd.compute_list_begin(); _rd.compute_list_bind_compute_pipeline(list,_programs["light"]["pipeline"]); _rd.compute_list_bind_uniform_set(list,_light_set,0)
        _rd.compute_list_set_push_constant(list,PackedInt32Array([0,0,0,0]).to_byte_array(),16)
        _rd.compute_list_dispatch(list,16,1,1); _rd.compute_list_end(); node_builds += 1; _transport_serial = transport.frame_count
        _stamp(profile,owner,serial,"node_response","end")
    _stamp(profile,owner,serial,"shading","begin")
    var list: int = _rd.compute_list_begin(); _rd.compute_list_bind_compute_pipeline(list,_programs["light"]["pipeline"]); _rd.compute_list_bind_uniform_set(list,_light_set,0)
    _rd.compute_list_set_push_constant(list,PackedInt32Array([1,0,0,0]).to_byte_array(),16)
    _rd.compute_list_dispatch(list,ceili(float(_size*_size)/64.),1,1); _rd.compute_list_end(); shade_builds += 1
    _stamp(profile,owner,serial,"shading","end")
    return {"primary_build":primary_dirty,"shadow_build":shadow_dirty,"changed_lights":changed_lights.size(),"node_builds":node_builds,"backend":backend}

func invalidate() -> void:
    _camera_key = PackedByteArray(); _shadow_keys.clear(); _transport_serial = -1

func capture() -> Dictionary:
    return {"surface_world":_rd.texture_get_data(_world,0).to_float32_array(),"surface_normal_half":_rd.texture_get_data(_normal,0),"surface_color_half":_rd.texture_get_data(_color,0),"native_depth":_rd.texture_get_data(_primary_depth,0).to_float32_array()}

func release() -> void:
    if _rd == null: return
    for rid in _sets:
        if _rd.uniform_set_is_valid(rid): _rd.free_rid(rid)
    for rid in _frames:
        if _rd.framebuffer_is_valid(rid): _rd.free_rid(rid)
    for entry in _programs.values():
        for rid in [entry["pipeline"],entry["shader"]]:
            if rid.is_valid(): _rd.free_rid(rid)
    for rid in _textures + _buffers:
        if rid.is_valid(): _rd.free_rid(rid)
    if _sampler.is_valid(): _rd.free_rid(_sampler)
    _sets.clear(); _frames.clear(); _textures.clear(); _buffers.clear(); _programs.clear(); _shadow_frames.clear(); requested_bytes = 0
