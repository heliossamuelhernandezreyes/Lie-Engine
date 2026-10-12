extends "res://lie31_hd_effect.gd"
## LIE33 software/hardware Vulkan dispatch tiling, preserving the exact LIE31
## PBR samples and GPU buffers. Previously 1080² exceeded 65,535 workgroups
## on stage 1/4/6 with 2160² internal pixels.
const TiledShader=preload("res://shaders/lie33_tiled_brick.glsl")
var tiled_dispatches: int=0
var max_y_groups: int=0

func shader_resource() -> RDShaderFile:return TiledShader
func _init(size: int=1080) -> void:
    super._init(512)
    output_size=clampi(size,720,1080)
    render_size=output_size*2

func _render_callback(_type: int,_data: RenderData) -> void:
    if not capture_loaded or (not gpu_ready and not _initialize()):return
    _mutex.lock();var next: Dictionary=_pending.duplicate();_mutex.unlock()
    if next.is_empty():return
    _collect_profile()
    var signature: PackedByteArray=next["parameters"].duplicate();signature.append_array(next["instances"]);signature.append_array(next["jobs"])
    if signature==_resident:return
    var work: int=next["work"]
    if work>projection_capacity:
        _rd.free_rid(_set);_set=RID()
        _rd.free_rid(_buffers[3]);allocation_bytes-=int(_lengths[3]);projection_capacity=mini(MAX_WORK,int(ceil(float(work)/65536))*65536)
        _buffer(3,projection_capacity*96);_make_set()
    _rd.buffer_update(_buffers[6],0,256,next["parameters"])
    _rd.buffer_update(_buffers[1],0,next["instances"].size(),next["instances"])
    _rd.buffer_update(_buffers[2],0,next["jobs"].size(),next["jobs"])
    _rd.capture_timestamp("lie22-begin")
    var list: int=_rd.compute_list_begin();_rd.compute_list_bind_compute_pipeline(list,_pipeline);_rd.compute_list_bind_uniform_set(list,_set,0)
    for stage in [1,2,3,4,6,7]:
        var count: int=work if stage in [2,3] else maxi(render_size*render_size,512*512) if stage==1 else output_size*output_size if stage==7 else render_size*render_size
        _rd.compute_list_set_push_constant(list,PackedInt32Array([stage,2,0,0]).to_byte_array(),16)
        # One dispatch per stage, with up to 65535 groups on X and overflow groups on Y.
        # The tiled shader uses gl_NumWorkGroups.x to linearize those groups.
        var groups: int=int(ceil(float(count)/64))
        var group_x: int=mini(groups,65535)
        var group_y: int=int(ceil(float(groups)/float(group_x)))
        if group_y>1:tiled_dispatches+=1
        max_y_groups=maxi(max_y_groups,group_y)
        if group_x<1 or group_y<1 or group_y>65535:
            failure="GPU compute workgroups outside Vulkan limits";_rd.compute_list_end();return
        _rd.compute_list_dispatch(list,group_x,group_y,1);_rd.compute_list_add_barrier(list)
    _rd.compute_list_end();_rd.capture_timestamp("lie22-end")
    _resident=signature;sample_invocations=work;instance_count=next["instances"].size()/96;frame_count+=1

