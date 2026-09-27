extends RigidBody3D
## Golf ball: left-click to select + drag to aim (slingshot), release to shoot.
## Pull distance scales shot force; the ball shoots opposite the drag direction.

@export var max_drag_distance: float = 1.5   # world-space drag length for full power
@export var max_force: float = 15.0           # impulse magnitude at full pull
@export var rest_speed: float = 0.05          # below this the ball counts as fully stopped
@export var settle_speed: float = 0.15        # below this the ball brakes to a full stop

const AIM_SHADER := preload("res://shaders/aim_line.gdshader")
const WATER_LEVEL := -3.0                      # water surface y (matches the Water node)
const BALL_RADIUS := 0.035                     # matches the sphere collider radius
const BUOYANCY := 30.0                         # upward force (N) at full submersion
const WATER_DRAG := 4.0                        # velocity damping per second in water
const MAX_UP_SPEED := 1.2                      # cap on upward speed (stops weird launches)
const IMPACT_DV := 0.9                         # per-frame velocity jump that counts as a hit
const IMPACT_COOLDOWN := 0.09                  # min seconds between hit sounds

var _aiming := false
var _drag_start := Vector3.ZERO    # world point on the floor where the drag began
var _drag_current := Vector3.ZERO  # world point on the floor under the mouse now
var _settle_cooldown := 0.0        # seconds to skip the settle brake after a shot
var _line_mat: ShaderMaterial
var _prev_vel := Vector3.ZERO      # previous frame velocity (impact detection)
var _impact_cd := 0.0
var _in_water := false

@onready var _line: MeshInstance3D = $AimLine
@onready var _impact_sfx: AudioStreamPlayer3D = $ImpactSound
@onready var _splash_sfx: AudioStreamPlayer3D = $SplashSound
@onready var _foam: CPUParticles3D = $SplashFoam


func _ready() -> void:
    _line.visible = false
    _line_mat = ShaderMaterial.new()
    _line_mat.shader = AIM_SHADER
    _line.material_override = _line_mat


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    # Cap upward speed so odd collisions can't launch the ball high into the air.
    var v := state.linear_velocity
    if v.y > MAX_UP_SPEED:
        v.y = MAX_UP_SPEED
        state.linear_velocity = v


func _physics_process(delta: float) -> void:
    _impact_cd = maxf(0.0, _impact_cd - delta)
    _detect_impact()
    if _apply_water(delta):
        return
    if _aiming or sleeping:
        return
    if _settle_cooldown > 0.0:
        _settle_cooldown -= delta
        return
    # Rolling resistance: once the ball crawls below settle_speed, brake it to a
    # clean stop so it sleeps and aiming unlocks promptly.
    if linear_velocity.length() < settle_speed:
        linear_velocity = Vector3.ZERO
        angular_velocity = Vector3.ZERO


## Plays a hit sound when the ball's velocity changes abruptly (a collision).
func _detect_impact() -> void:
    var dv := (linear_velocity - _prev_vel).length()
    _prev_vel = linear_velocity
    if sleeping or dv < IMPACT_DV or _impact_cd > 0.0:
        return
    _impact_cd = IMPACT_COOLDOWN
    _impact_sfx.pitch_scale = randf_range(0.92, 1.12)
    _impact_sfx.volume_db = linear_to_db(clampf(dv / 6.0, 0.12, 1.0))
    _impact_sfx.play()


## Buoyancy: keeps the ball afloat once it drops into the water. Returns true
## while the ball is in the water (so the settle brake is skipped).
func _apply_water(delta: float) -> bool:
    var depth := WATER_LEVEL - global_position.y
    if depth < -BALL_RADIUS:
        _in_water = false
        return false
    if not _in_water:
        _in_water = true
        _splash_sfx.play()
        _foam.global_position = Vector3(global_position.x, WATER_LEVEL + 0.02, global_position.z)
        _foam.restart()
    sleeping = false
    var sub := clampf((depth + BALL_RADIUS) / (2.0 * BALL_RADIUS), 0.0, 1.0)
    apply_central_force(Vector3.UP * sub * BUOYANCY)
    var damp := clampf(1.0 - WATER_DRAG * delta, 0.0, 1.0)
    linear_velocity *= damp
    angular_velocity *= damp
    return true


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            if _can_aim():
                var p := _mouse_floor_point(event.position)
                if p != Vector3.INF:
                    _drag_start = p
                    _drag_current = p
                    _aiming = true
                    _update_line()
        else:
            if _aiming:
                _aiming = false
                _shoot()
    elif event is InputEventMouseMotion and _aiming:
        var p := _mouse_floor_point(event.position)
        if p != Vector3.INF:
            _drag_current = p
            _update_line()


func _can_aim() -> bool:
    return sleeping or linear_velocity.length() < rest_speed


func _shoot() -> void:
    _line.visible = false
    var drag := _drag_current - _drag_start
    drag.y = 0.0
    if drag.length() < 0.05:
        return  # drag too short — cancel the shot
    var dir := -drag.normalized()
    var power := clampf(drag.length() / max_drag_distance, 0.0, 1.0)
    sleeping = false
    apply_central_impulse(dir * (power * max_force))
    _settle_cooldown = 0.5


func _update_line() -> void:
    var drag := _drag_current - _drag_start
    drag.y = 0.0
    var length := clampf(drag.length(), 0.0, max_drag_distance)
    if length < 0.05:
        _line.visible = false
        return
    var dir := -drag.normalized()
    _line.visible = true
    # Dotted line lying on the ground, starting at the ball and running toward the
    # shoot direction; it stretches with the pull.
    var origin := Vector3(global_position.x, global_position.y - 0.02, global_position.z)
    _line.global_position = origin + dir * (length * 0.5)
    _line.rotation = Vector3(0.0, atan2(dir.x, dir.z), 0.0)
    _line.scale = Vector3(0.2, 1.0, length)
    _line_mat.set_shader_parameter("start_pos", origin)
    _line_mat.set_shader_parameter("dir", Vector2(dir.x, dir.z))


## Ray from the camera through the mouse, intersected with the floor plane (y=0).
## Returns Vector3.INF when the ray is parallel to / misses the floor (e.g. looking up).
func _mouse_floor_point(mouse_pos: Vector2) -> Vector3:
    var cam := get_viewport().get_camera_3d()
    if cam == null:
        return Vector3.INF
    var from := cam.project_ray_origin(mouse_pos)
    var dir := cam.project_ray_normal(mouse_pos)
    if absf(dir.y) < 0.0001:
        return Vector3.INF
    var t := -from.y / dir.y
    if t < 0.0:
        return Vector3.INF
    return from + dir * t
