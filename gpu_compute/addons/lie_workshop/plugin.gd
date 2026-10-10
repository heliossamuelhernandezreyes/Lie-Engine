@tool
extends EditorPlugin
var dock: VBoxContainer
func _enter_tree() -> void:
    dock=VBoxContainer.new(); dock.name="Lie"
    var label:=Label.new(); label.text="Lie · Taller de piezas"; dock.add_child(label)
    var button:=Button.new(); button.text="Abrir taller"
    button.pressed.connect(func(): EditorInterface.play_custom_scene("res://lie18_workshop.tscn"))
    dock.add_child(button)
    var hint:=Label.new(); hint.text="Piezas · articulaciones · animación\nControles compartidos con agentes"; dock.add_child(hint)
    add_control_to_dock(DOCK_SLOT_LEFT_UL,dock)
func _exit_tree() -> void:
    remove_control_from_docks(dock); dock.queue_free()
