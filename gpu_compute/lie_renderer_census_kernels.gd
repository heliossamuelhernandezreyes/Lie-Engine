extends RefCounted
## Generated diagnostic copies, not performance kernels.
const SHADERS={
	2:preload("res://shaders/lie_renderer_census_02.glsl"),
	3:preload("res://shaders/lie_renderer_census_03.glsl"),
	4:preload("res://shaders/lie_renderer_census_04.glsl"),
	10:preload("res://shaders/lie_renderer_census_10.glsl"),
	11:preload("res://shaders/lie_renderer_census_11.glsl"),
}
const BINDINGS={2:[0,1,2,3,4,5,6,7,16,17,28,29,32,36,49],3:[0,1,2,3,4,5,6,7,16,17,28,29,32,36,49],4:[3,5,6,7,8,9,11,14,15,21,33,49],10:[0,1,3,5,6,7,8,9,15,18,19,21,22,23,24,28,32,33,34,49],11:[0,3,6,22,23,25,26,27,28,30,31,35,39,49]}
const NAMES=["selected_sample_invocations","project_active","project_candidates","raster_candidates","material_contributions","base_node_evaluations","refined_pixels","refined_group_nodes","refined_light_node_evaluations","local_light_evaluations","source_light_pairs","shadow_cache_hits","witness_attempts","witness_hits","full_shadow_traversals","scene_nodes","blas_nodes","disk_tests"]
