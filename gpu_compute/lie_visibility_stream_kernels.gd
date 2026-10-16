extends RefCounted
const SHADERS={
    "mark":preload("res://shaders/lie_wall19_mark.glsl"),
    "compact":preload("res://shaders/lie_wall19_compact.glsl"),
    "prepare":preload("res://shaders/lie_wall19_prepare.glsl"),
    "trace":preload("res://shaders/lie_wall19_trace.glsl"),
    "reset":preload("res://shaders/lie_wall19_reset.glsl"),
}
const BINDINGS={"mark":[5,6,28],"compact":[6,28,35,37],"prepare":[0,3,6,22,23,27,28,30,31,35,38,39],"trace":[0,3,22,23,25,26,27,28,30,31,38,39],"reset":[38,39]}
