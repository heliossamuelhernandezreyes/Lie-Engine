extends "res://lie10_blender_effect.gd"
## Same GPU reprojection/depth composition, new grayscale/material/node consumer.
const CodedShader: RDShaderFile=preload("res://shaders/lie12_pipeline.glsl")
const ROOT: String="res://captures/coded_shard/"
var lighting: CompositorEffect
var metadata: Dictionary={}
var base_model: Dictionary={}
var _pixel_filters:=PackedFloat32Array()
var _distance_scale: float=1.0

func _make_blender_capture() -> void:
    var path: String=ROOT+"code-manifest.json"
    if not FileAccess.file_exists(path): return
    var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
    var model: Variant=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"light-model.json"))
    if not value is Dictionary or not model is Dictionary: return
    metadata=value
    base_model=model
    if int(metadata.get("schema",0))!=1 or int(metadata.get("sample_count",0))!=SAMPLE_COUNT: return
    var pixel_file: FileAccess=FileAccess.open(ROOT+"pixel-codes.bin",FileAccess.READ)
    var sample_file: FileAccess=FileAccess.open(ROOT+"sample-normal.bin",FileAccess.READ)
    if pixel_file==null or sample_file==null: return
    if pixel_file.get_length()!=SAMPLE_COUNT*32 or sample_file.get_length()!=SAMPLE_COUNT*32: return
    var pixels: PackedFloat32Array=pixel_file.get_buffer(pixel_file.get_length()).to_float32_array()
    var geometry: PackedFloat32Array=sample_file.get_buffer(sample_file.get_length()).to_float32_array()
    for i in range(SAMPLE_COUNT):
        var node: int=roundi(pixels[i*8+7])
        var valid: bool=pixels[i*8+3]>.5 and node>=0 and node<(base_model["patches"] as Array).size()
        if valid and (absf(pixels[i*8]-pixels[i*8+1])>.000001 or absf(pixels[i*8]-pixels[i*8+2])>.000001): return
        _samples.append_array(PackedFloat32Array([geometry[i*8],geometry[i*8+1],geometry[i*8+2],1.0 if valid else 0.0]))
        _normals.append_array(PackedFloat32Array([geometry[i*8+4],geometry[i*8+5],geometry[i*8+6],0.0]))
        _colors.append_array(PackedFloat32Array([pixels[i*8],pixels[i*8+1],pixels[i*8+2],1.0 if valid else 0.0]))
        _pixel_filters.append_array(PackedFloat32Array([pixels[i*8+4],pixels[i*8+5],pixels[i*8+6],float(node)]))
        _attributes.append_array(PackedFloat32Array([float(i/(SOURCE_SIZE*SOURCE_SIZE)),1.0,1.0,0.0]))
        if valid: captured_valid_pixels+=1
    _capture_radius=float(metadata["capture_radius"])
    _capture_scale=float(metadata["ortho_scale"])
    _near_source=float(metadata["near"])
    _far_source=float(metadata["far"])
    capture_loaded=captured_valid_pixels>1000

func _reprojection_file() -> RDShaderFile:
    return CodedShader

func _light_data(_mode: int) -> PackedFloat32Array:
    return _pixel_filters

func _initialize_gpu() -> bool:
    if lighting==null or not bool(lighting.get("gpu_ready")): return false
    return super._initialize_gpu()

func _extra_reprojection_uniforms() -> Array[RDUniform]:
    var light_buffers: Array=lighting.get("_buffers")
    return [_make_image_uniform(11,lighting.get("output_rid")),_make_storage_uniform(12,light_buffers[0])]

func set_distance_scale(value: float) -> void:
    _mutex.lock()
    var next: float=clampf(value,.6,2.0)
    if next!=_distance_scale:
        _distance_scale=next
        _applied_yaw_degrees=INF
    _mutex.unlock()

func camera_position(yaw: float, scale_value: float=1.0) -> Vector3:
    var angle: float=deg_to_rad(yaw)
    var elevation: float=deg_to_rad(float(metadata.get("camera_elevation",20)))
    return Vector3(sin(angle)*cos(elevation),sin(elevation),cos(angle)*cos(elevation))*_capture_radius*3.5*scale_value

func _camera_data(yaw: float) -> PackedFloat32Array:
    var data:=PackedFloat32Array()
    var eye: Vector3=camera_position(yaw,_distance_scale)
    var forward: Vector3=-eye.normalized()
    var right: Vector3=forward.cross(Vector3.UP).normalized()
    var up: Vector3=right.cross(forward).normalized()
    for source in metadata["sources"]:
        for value in [source["origin"],source["right"],source["up"],source["forward"],
                [eye.x,eye.y,eye.z],[right.x,right.y,right.z],[up.x,up.y,up.z],[forward.x,forward.y,forward.z]]:
            data.append_array(PackedFloat32Array([float(value[0]),float(value[1]),float(value[2]),0.0]))
        data.append_array(PackedFloat32Array([_capture_scale,_near_source,_far_source,0.0,tan(deg_to_rad(60.0)*.5),1.0,.1,100.0]))
    return data
