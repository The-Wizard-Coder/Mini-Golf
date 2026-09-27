extends Node
## Drives the level sequence: instances each level, tees the ball at its start,
## and advances when a level signals `level_over`. In endless mode the levels are
## generated rather than loaded, seeded by a counter that only ever counts up.

@export var levels: Array[PackedScene] = []
@export var endless_level: PackedScene
@export var ball_path: NodePath
@export var level_container_path: NodePath
@export var ui_path: NodePath
@export var camera_path: NodePath
@export var menu_scene: String = "res://scenes/main_menu.tscn"
@export var fail_y: float = -1.5      # ball below this = fell into the water
@export var fail_delay: float = 1.5   # seconds in the water before the fail screen

var _index := -1
var _seed := 0                        # endless mode: the run counter, also the seed
var _endless := false
var _current: GolfLevel
var _fail_timer := 0.0

@onready var _ball: RigidBody3D = get_node(ball_path)
@onready var _container: Node3D = get_node(level_container_path)
@onready var _ui: LevelOverUI = get_node(ui_path)
@onready var _camera: Camera3D = get_node_or_null(camera_path) as Camera3D
@onready var _loading: CanvasLayer = %LoadingOverlay


func _ready() -> void:
    _ui.next_pressed.connect(_on_next_pressed)
    _ui.retry_pressed.connect(_on_retry_pressed)
    _ui.menu_pressed.connect(_on_menu_pressed)
    start()


func _process(delta: float) -> void:
    if _ui.visible:
        return
    if _ball.global_position.y < fail_y:
        _fail_timer += delta
        if _fail_timer >= fail_delay:
            _fail_timer = 0.0
            _ui.show_fail()
    else:
        _fail_timer = 0.0


## The first level has to upload its meshes and compile the tile, water and
## post-process shaders before it can draw anything, and on the web that stalls
## the main thread for a moment. So show the loading layer, let it actually get
## presented, and only then build the level - the stall then happens behind a
## message instead of an empty sky.
func start() -> void:
    _endless = GameMode.endless
    await _settle_frames(2)
    if _endless:
        _load_generated(0)
    else:
        _load_level(0)
    await _settle_frames(3)
    _loading.visible = false


func _settle_frames(count: int) -> void:
    for i in count:
        await get_tree().process_frame


func _load_level(i: int) -> void:
    _index = i
    _swap_in(levels[i].instantiate())


## Endless: the run counter is the seed, so every hole is reproducible and the
## sequence never has to end.
func _load_generated(n: int) -> void:
    _seed = n
    var level: GolfLevel = endless_level.instantiate()
    level.set(&"seed_value", n)
    _swap_in(level)


func _swap_in(level: GolfLevel) -> void:
    if _current != null:
        _current.queue_free()
        _current = null
    _ui.hide_ui()
    _current = level
    _container.add_child(_current)
    _current.level_over.connect(_on_level_over)
    _place_ball()
    _aim_camera()


## Look from the tee toward the hole, so the goal is always "into the screen".
## With a fixed isometric view the player otherwise has no cue which way to hit.
func _aim_camera() -> void:
    if _camera == null or not _camera.has_method("face_towards"):
        return
    _camera.face_towards(_current.hole_position() - _current.start_position())


func _place_ball() -> void:
    _ball.global_position = _current.start_position() + Vector3(0.0, 0.2, 0.0)
    _ball.linear_velocity = Vector3.ZERO
    _ball.angular_velocity = Vector3.ZERO
    _ball.sleeping = false


func _on_level_over() -> void:
    await get_tree().create_timer(0.7).timeout
    if _endless:
        _ui.show_endless(_seed + 1)
    elif _index + 1 < levels.size():
        _ui.show_next(_index + 1, levels.size())
    else:
        _ui.show_complete()


func _on_next_pressed() -> void:
    if _endless:
        _load_generated(_seed + 1)
    elif _index + 1 < levels.size():
        _load_level(_index + 1)


func _on_retry_pressed() -> void:
    if _endless:
        _load_generated(_seed)
    else:
        _load_level(_index)


func _on_menu_pressed() -> void:
    get_tree().change_scene_to_file(menu_scene)
