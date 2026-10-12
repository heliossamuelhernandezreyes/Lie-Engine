extends "res://lie_robot_effect.gd"
## The same compositor owns robot and architecture depth, shading and shadows.
func capture_root() -> String:return "res://captures/robot_world/"
func maximum_instances() -> int:return 192
func maximum_work() -> int:return 1300000
