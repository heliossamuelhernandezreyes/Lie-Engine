extends Node3D
## A manually authored, STATIC, completely opaque rectangular visibility proxy.
## The rectangle lies on the node's local XY plane, local Z is its normal.
## This does not render a wall; the game must supply an actual opaque wall.
## Never enable for windows, holes, moveable/translucent blockers.
@export var lie_opaque: bool = true
@export var half_extent := Vector2(3.0, 2.0)

func _enter_tree() -> void:
    add_to_group("lie_occluders")

func _exit_tree() -> void:
    remove_from_group("lie_occluders")
