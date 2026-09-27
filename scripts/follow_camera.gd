extends Camera3D
## Follows the target ball. Orbit (right-drag) can be frozen; wheel zoom stays active.

@export var target_path: NodePath
@export var distance: float = 1.5            # orbit radius
@export var pitch_deg: float = 35.264        # elevation above horizon (isometric)
@export var yaw_deg: float = 45.0            # azimuth (isometric)
@export var orbit_enabled: bool = false      # right-drag orbit on/off
@export var orbit_speed: float = 0.005       # radians per pixel of drag
@export var zoom_step: float = 0.12          # multiplicative wheel-zoom factor
@export var min_distance: float = 0.4
@export var max_distance: float = 15.0
@export var min_pitch_deg: float = 5.0       # keep the mouse ray from going parallel to the floor
@export var max_pitch_deg: float = 85.0

var _target: Node3D
var _orbiting := false
var _pitch := 0.0
var _yaw := 0.0


func _ready() -> void:
    _pitch = deg_to_rad(pitch_deg)
    _yaw = deg_to_rad(yaw_deg)
    if target_path != null and not target_path.is_empty():
        _target = get_node(target_path)


## Aim the camera so the world direction `dir` reads as "into the screen", with
## the ball centred. Levels call this with tee -> hole, so the goal always sits
## straight ahead and the player knows which way to hit.
func face_towards(dir: Vector3) -> void:
    var flat := Vector3(dir.x, 0.0, dir.z)
    if flat.length_squared() < 0.0001:
        return
    flat = flat.normalized()
    # The camera orbits round to the side opposite the way it looks.
    _yaw = atan2(-flat.x, -flat.z)


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
        distance = clampf(distance * (1.0 - zoom_step), min_distance, max_distance)
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
        distance = clampf(distance * (1.0 + zoom_step), min_distance, max_distance)
    elif not orbit_enabled:
        return
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
        _orbiting = event.pressed
    elif event is InputEventMouseMotion and _orbiting:
        _yaw -= event.relative.x * orbit_speed
        _pitch = clampf(
            _pitch - event.relative.y * orbit_speed,
            deg_to_rad(min_pitch_deg),
            deg_to_rad(max_pitch_deg)
        )


func _process(_delta: float) -> void:
    if _target == null:
        return
    var offset := Vector3(
        distance * cos(_pitch) * sin(_yaw),
        distance * sin(_pitch),
        distance * cos(_pitch) * cos(_yaw)
    )
    global_position = _target.global_position + offset
    look_at(_target.global_position, Vector3.UP)
