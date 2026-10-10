extends "res://lie17_capture_effect.gd"
const Pipeline18: RDShaderFile=preload("res://shaders/lie18_pipeline.glsl")
const Temporal18: RDShaderFile=preload("res://shaders/lie18_temporal.glsl")
var masters: Dictionary={}

func pipeline_file() -> RDShaderFile: return Pipeline18
func temporal_file() -> RDShaderFile: return Temporal18
func instance_capacity() -> int: return 30
func render_poses() -> Array[Transform3D]:
    var poses: Array[Transform3D]=[]
    if lighting!=null: poses.assign(lighting.get("render_poses"))
    return poses
func render_signature() -> String: return str(lighting.get("render_signature"))

func _load_master() -> void:
    var merged:=PackedFloat32Array(); var widths:=PackedByteArray()
    for entry in [["box","res://captures/robot_master/"],["cylinder","res://captures/workshop_cylinder/"]]:
        var root: String=entry[1]
        var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(root+"quality-master.json")) if FileAccess.file_exists(root+"quality-master.json") else null
        if not parsed is Dictionary: failure="Prepare workshop captures: "+root; return
        var metadata: Dictionary=parsed
        if metadata.get("quality_schema")!=1 or metadata.get("levels",[]).size()!=3 or int(metadata.get("sample_count",0))>524287: return
        if FileAccess.get_sha256(root+"quality-samples.bin")!=metadata.get("sample_sha256") or FileAccess.get_sha256(root+"quality-footprints.bin")!=metadata.get("footprint_sha256"): return
        var file:=FileAccess.open(root+"quality-samples.bin",FileAccess.READ)
        var fp:=FileAccess.open(root+"quality-footprints.bin",FileAccess.READ)
        if file==null or fp==null or file.get_length()!=int(metadata["sample_count"])*32 or fp.get_length()!=int(metadata["sample_count"])*4: return
        var offset: int=merged.size()/8
        var sample_data: PackedFloat32Array=file.get_buffer(file.get_length()).to_float32_array()
        for i in range(int(metadata["sample_count"])):
            var n:=Vector3(sample_data[i*8+4],sample_data[i*8+5],sample_data[i*8+6])
            if not n.is_finite() or absf(n.length_squared()-1)>.001 or roundi(sample_data[i*8+7]) not in range(6): return
        for level in metadata["levels"]:
            if level.size()!=60: return
            for view in level:
                if int(view["start"])<0 or int(view["count"])<1 or int(view["start"])+int(view["count"])>int(metadata["sample_count"]): return
                view["start"]=int(view["start"])+offset
        for i in range(metadata["probe_samples"].size()): metadata["probe_samples"][i]=int(metadata["probe_samples"][i])+offset
        masters[entry[0]]=metadata
        merged.append_array(sample_data); widths.append_array(fp.get_buffer(fp.get_length()))
    samples=merged; _footprints=widths
    master=masters["box"].duplicate(true); master["sample_count"]=samples.size()/8
    capture_loaded=true

func _make_set() -> void:
    var bindings: Array=[0,1,2,3,4,5,16,17,6,20,21,22]
    var uniforms: Array[RDUniform]=[]
    for i in range(bindings.size()): uniforms.append(_uniform(int(bindings[i]),_buffers[i]))
    uniforms.append(_uniform(7,_output,true))
    var producer: Array=lighting.get("_buffers")
    uniforms.append_array([_uniform(11,lighting.get("output_rid"),true),_uniform(12,producer[0]),_uniform(14,lighting.get("instance_rid")),_uniform(15,lighting.get("direct_rid"),true),_uniform(18,producer[1]),_uniform(19,producer[4]),_uniform(23,producer[12]),_uniform(24,producer[8])])
    _set=_rd.uniform_set_create(uniforms,_shader,0)

func probe_codes() -> PackedInt32Array:
    var probes:=PackedInt32Array()
    var slots: Array=lighting.get("render_slots")
    for i in range(30):
        var source: Dictionary=masters[slots[i] if slots[i]!="" else "box"]
        for sample in source["probe_samples"]: probes.append_array(PackedInt32Array([int(sample),i,0,0]))
    return probes

func _jobs(poses: Array[Transform3D],eye: Transform3D,tan_y: float,aspect: float,adaptive: bool) -> PackedFloat32Array:
    var data:=PackedFloat32Array(); var work: int=0
    var slots: Array=lighting.get("render_slots")
    visible_instances=0; _lod_counts=PackedInt32Array([0,0,0])
    for instance in range(poses.size()):
        if slots[instance]=="": continue
        var source: Dictionary=masters[slots[instance]]
        var pose: Transform3D=poses[instance]
        if not Rigid.box_visible(pose,eye,tan_y,aspect): continue
        visible_instances+=1
        var local_direction: Vector3=(pose.basis.inverse()*(eye.origin-pose.origin)).normalized()
        var depth: float=-(eye.basis.inverse()*(pose.origin-eye.origin)).z
        var scale: float=maxf(pose.basis.x.length(),maxf(pose.basis.y.length(),pose.basis.z.length()))
        var spacing: float=float(source["pixel_size_local"])*scale*render_size/(2*tan_y*maxf(depth-pose.basis.get_scale().length()*.5,.1))
        var weights: Vector3=_lod_weights(spacing) if adaptive else Vector3(1,0,0)
        for level in range(3):
            if weights[level]<.0001: continue
            for view in source["levels"][level]:
                var weight: float=pow(maxf(2*Rigid.Model.vector(view["direction"]).dot(local_direction)-1,0),2)*weights[level]
                if weight<=.00001: continue
                var count: int=int(view["count"])
                data.append_array(PackedFloat32Array([float(view["start"]),float(count),float(instance),weight,float(work),float(work+count),float(level),0]))
                for axis in ["right","up","forward"]:
                    var v: Vector3=Rigid.Model.vector(view[axis]); data.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
                work+=count; _lod_counts[level]+=count
    sample_invocations=work
    return data
