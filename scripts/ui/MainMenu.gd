extends Control
class_name MainMenu

## 主菜单界面

@export var start_button: Button
@export var exit_button: Button
@export var game_scene_path: String = "res://main.tscn"

func _ready() -> void:
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if exit_button:
		exit_button.pressed.connect(_on_exit_pressed)

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(game_scene_path)

func _on_exit_pressed() -> void:
	get_tree().quit()
