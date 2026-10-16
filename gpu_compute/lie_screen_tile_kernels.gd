extends RefCounted
## Generated screen-tile shaders; original source identity and pixel math.
const SHADERS={
    "reset":preload("res://shaders/lie_wall22_reset.glsl"),
    "project":preload("res://shaders/lie_wall22_project.glsl"),
    "scan":preload("res://shaders/lie_wall22_scan.glsl"),
    "groups":preload("res://shaders/lie_wall22_groups.glsl"),
    "fill":preload("res://shaders/lie_wall22_fill.glsl"),
    "resolve":preload("res://shaders/lie_wall22_resolve.glsl"),
}
const BINDINGS={"reset":[6,41],"project":[0,1,2,3,6,16,17,29,36,41,44],"scan":[6,41,43],"groups":[6,43],"fill":[2,3,6,29,36,41,42,43],"resolve":[3,4,5,6,7,16,28,32,41,42,43,44]}
