extends Control
## Main menu: campaign, endless (generated holes) or quit.

const GAME_SCENE := "res://scenes/game.tscn"


func _ready() -> void:
    %StartButton.pressed.connect(_on_start_pressed)
    %EndlessButton.pressed.connect(_on_endless_pressed)
    %QuitButton.pressed.connect(_on_quit_pressed)
    %StartButton.grab_focus()


func _on_start_pressed() -> void:
    GameMode.endless = false
    get_tree().change_scene_to_file(GAME_SCENE)


func _on_endless_pressed() -> void:
    GameMode.endless = true
    get_tree().change_scene_to_file(GAME_SCENE)


func _on_quit_pressed() -> void:
    get_tree().quit()
