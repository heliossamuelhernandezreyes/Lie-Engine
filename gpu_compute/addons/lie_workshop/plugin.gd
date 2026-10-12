@tool
extends EditorPlugin
var dock: VBoxContainer
func _enter_tree() -> void:
    dock=VBoxContainer.new(); dock.name="Lie"
    var label:=Label.new(); label.text="Lie · Taller de piezas"; dock.add_child(label)
    var button:=Button.new(); button.text="Abrir taller"
    button.pressed.connect(func(): EditorInterface.play_custom_scene("res://lie18_workshop.tscn"))
    dock.add_child(button)
    var anatomy:=Button.new();anatomy.text="Abrir anatomía y rostro · LIE-27"
    anatomy.pressed.connect(func():EditorInterface.play_custom_scene("res://lie27_regions_lab.tscn"));dock.add_child(anatomy)
    var building:=Button.new();building.text="Abrir construcción modular · LIE-28"
    building.pressed.connect(func():EditorInterface.play_custom_scene("res://lie28_building_lab.tscn"));dock.add_child(building)
    var brick:=Button.new();brick.text="LIE29 · Pared de ladrillos"
    brick.pressed.connect(func():EditorInterface.play_custom_scene("res://lie29_brick_wall_lab.tscn"));dock.add_child(brick)
    var masonry:=Button.new();masonry.text="LIE30 · Mampostería"
    masonry.pressed.connect(func():EditorInterface.play_custom_scene("res://lie30_masonry_lab.tscn"));dock.add_child(masonry)
    var hd:=Button.new();hd.text="LIE31 · Ladrillo HD"
    hd.pressed.connect(func():EditorInterface.play_custom_scene("res://lie31_hd_lab.tscn"));dock.add_child(hd)
    var hint:=Label.new(); hint.text="Piezas · articulaciones · animación\nControles compartidos con agentes"; dock.add_child(hint)
    add_control_to_dock(DOCK_SLOT_LEFT_UL,dock)
func _exit_tree() -> void:
    remove_control_from_docks(dock); dock.queue_free()
