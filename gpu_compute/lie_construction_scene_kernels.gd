extends RefCounted
const SHADERS={
    1:preload("res://shaders/lie_construction_scene_stage_1.glsl"),
    2:preload("res://shaders/lie_construction_scene_stage_2.glsl"),
    3:preload("res://shaders/lie_construction_scene_stage_3.glsl"),
    4:preload("res://shaders/lie_construction_scene_stage_4.glsl"),
    6:preload("res://shaders/lie_construction_scene_stage_6.glsl"),
    7:preload("res://shaders/lie_construction_scene_stage_7.glsl"),
}
const BINDINGS={1:[4,5,6,7,13],2:[0,1,2,3,4,5,6,7,13,14],3:[0,1,2,3,4,5,6,7,13,14],4:[1,3,4,5,6,7,8,9,11,13],6:[1,3,4,5,6,7,8,9,11,13],7:[6,11,12]}
