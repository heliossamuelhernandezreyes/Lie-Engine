extends RefCounted
const SHADERS={
    1:preload("res://shaders/lie_construction_scene_stage_1.glsl"),
    2:preload("res://shaders/lie_construction_scene_stage_2.glsl"),
    3:preload("res://shaders/lie_construction_scene_stage_3.glsl"),
    4:preload("res://shaders/lie_construction_scene_stage_4.glsl"),
    6:preload("res://shaders/lie_construction_scene_stage_6.glsl"),
    7:preload("res://shaders/lie_construction_scene_stage_7.glsl"),
    8:preload("res://shaders/lie_construction_scene_stage_8.glsl"),
    9:preload("res://shaders/lie_construction_scene_stage_9.glsl"),
    10:preload("res://shaders/lie_construction_scene_stage_9.glsl"),
    11:preload("res://shaders/lie_construction_scene_stage_9.glsl"),
    12:preload("res://shaders/lie_construction_scene_stage_12.glsl"),
}
const LEGACY={
    2:preload("res://shaders/lie_construction_legacy_stage_2.glsl"),
    3:preload("res://shaders/lie_construction_legacy_stage_3.glsl"),
}
const PROBE={
    2:preload("res://shaders/lie_construction_probe_stage_2.glsl"),
    3:preload("res://shaders/lie_construction_probe_stage_3.glsl"),
    9:preload("res://shaders/lie_construction_probe_stage_9.glsl"),
    10:preload("res://shaders/lie_construction_probe_stage_9.glsl"),
    11:preload("res://shaders/lie_construction_probe_stage_9.glsl"),
    12:preload("res://shaders/lie_construction_probe_stage_12.glsl"),
}
const CAMERA_STAGES=[2,3,9,10,11,12]
const BINDINGS={8:[0,1,2,3,4,5,6,7,13,14,15,20],1:[4,5,6,7,13],2:[0,1,2,3,4,5,6,7,13,14,15,20],3:[0,1,2,3,4,5,6,7,13,14,15,20],4:[1,3,4,5,6,7,11,13,16,17,18,19],6:[1,3,4,5,6,7,8,9,11,13],7:[6,11,12],9:[0,1,2,3,4,5,6,7,13,14,15,20],10:[0,1,2,3,4,5,6,7,13,14,15,20],11:[0,1,2,3,4,5,6,7,13,14,15,20],12:[0,1,2,3,4,5,6,7,13,14,15,20]}
