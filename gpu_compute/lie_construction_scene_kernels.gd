extends RefCounted
const SHADERS={
    1:preload("res://shaders/lie_construction_scene_stage_1.glsl"),
    2:preload("res://shaders/lie_construction_scene_stage_2.glsl"),
    3:preload("res://shaders/lie_construction_scene_stage_3.glsl"),
    4:preload("res://shaders/lie_construction_scene_stage_4.glsl"),
    6:preload("res://shaders/lie_construction_scene_stage_6.glsl"),
    7:preload("res://shaders/lie_construction_scene_stage_7.glsl"),
    8:preload("res://shaders/lie_construction_scene_stage_8.glsl"),
}
const BINDINGS={8:[0,1,2,6,13,15,20],1:[4,5,6,7,13],2:[0,1,2,3,4,5,6,7,13,14,15,20],3:[0,1,2,3,4,5,6,7,13,14,15,20],4:[1,3,4,5,6,7,11,13,16,17,18,19],6:[1,3,4,5,6,7,8,9,11,13],7:[6,11,12]}
