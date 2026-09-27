extends CanvasLayer
class_name LevelOverUI
## Level-complete / fail overlay. One primary button whose meaning switches
## between "Next Level" and "Retry", plus a "Main Menu" button.

signal next_pressed
signal retry_pressed
signal menu_pressed

enum Mode { NEXT, RETRY }

var _mode := Mode.NEXT

@onready var _title: Label = %Title
@onready var _next: Button = %NextButton
@onready var _menu: Button = %MenuButton


func _ready() -> void:
	visible = false
	_next.pressed.connect(_on_primary_pressed)
	_menu.pressed.connect(func(): menu_pressed.emit())


func _on_primary_pressed() -> void:
	if _mode == Mode.RETRY:
		retry_pressed.emit()
	else:
		next_pressed.emit()


func hide_ui() -> void:
	visible = false


func show_next(level_num: int, total: int) -> void:
	visible = true
	_mode = Mode.NEXT
	_title.text = "Level %d / %d Complete!" % [level_num, total]
	_next.text = "Next Level"
	_next.visible = true
	_next.grab_focus()


## Endless mode: no total to report, just how far the run has got.
func show_endless(hole_num: int) -> void:
	visible = true
	_mode = Mode.NEXT
	_title.text = "Hole %d Complete!" % hole_num
	_next.text = "New Map"
	_next.visible = true
	_next.grab_focus()


func show_complete() -> void:
	visible = true
	_mode = Mode.NEXT
	_title.text = "All Levels Complete!"
	_next.visible = false
	_menu.grab_focus()


func show_fail() -> void:
	visible = true
	_mode = Mode.RETRY
	_title.text = "Water Hazard!"
	_next.text = "Retry"
	_next.visible = true
	_next.grab_focus()
