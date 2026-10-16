extends RefCounted
const SHADERS={
    "visibility":preload("res://shaders/lie_wall21_visibility.glsl"),
    "prepare":preload("res://shaders/lie_wall21_prepare.glsl"),
    "trace":preload("res://shaders/lie_wall21_trace.glsl"),
}
const BINDINGS={"visibility":[0,3,6,22,23,25,26,27,28,30,31,35,39],"prepare":[0,3,6,22,23,27,28,30,31,35,38,39],"trace":[0,3,22,23,25,26,27,28,30,31,38,39]}
