extends Node3D
class_name GolfLevel
## A playable level: GridMap geometry + a start Marker3D + a hole Area3D.
## Emits `level_over` only once the ball has settled *inside* the hole (stayed in
## the trigger and slowed down), so a ball that merely rolls across it doesn't win.

signal level_over

@export var hold_time: float = 0.3    # seconds the ball must stay in the hole
@export var max_speed: float = 0.3    # ball must be slower than this to count as "in"

@onready var _start: Marker3D = $Start
@onready var _hole: Area3D = $HoleArea

var _ball: RigidBody3D
var _inside := false
var _hold := 0.0
var _won := false


func _ready() -> void:
    _hole.body_entered.connect(_on_hole_entered)
    _hole.body_exited.connect(_on_hole_exited)
    _build_smooth_floor()
    _ensure_safe_spawn()


## A level is only playable if the ball starts somewhere it can actually sit: a
## cell that exists in the grid and is not the cup itself. Hand-placed markers
## and generated ones both pass through here, so a bad tee can never drop the
## ball into the sea or straight into the hole.
func _ensure_safe_spawn() -> void:
    var grid := get_node_or_null(^"GridMap") as GridMap
    if grid == null:
        return
    var cells := grid.get_used_cells()
    if cells.is_empty():
        return
    var hole := _hole.global_position
    var spawn := _start.global_position
    var spawn_cell := grid.local_to_map(grid.to_local(spawn))
    var on_floor := cells.has(spawn_cell) and not _has_no_floor(grid, spawn_cell)
    var clear_of_hole := Vector2(spawn.x - hole.x, spawn.z - hole.z).length() > 0.75
    if on_floor and clear_of_hole:
        return
    # Fall back to the solid cell furthest from the cup: on a corridor that is
    # the far end of the walk, which is where a tee belongs.
    var best := spawn
    var best_distance := -1.0
    for cell in cells:
        if _has_no_floor(grid, cell):
            continue                    # the cup and the gap are not a tee
        var point := grid.to_global(grid.map_to_local(cell))
        var distance := point.distance_to(hole)
        if distance > best_distance:
            best_distance = distance
            best = point
    if best_distance <= 0.0:
        return
    _start.global_position = Vector3(best.x, spawn.y, best.z)
    push_warning(
        "level: tee at %s was unusable, moved to %s" % [spawn, _start.global_position]
    )


# --- Collision floor ---------------------------------------------------------
# Each tile carries its own ConcavePolygonShape3D - one shape per cell. Where two
# cells meet, the ball rests on BOTH shapes at once and the two contact responses
# add up, which launches a rolling ball off the seam. Engine-side internal-edge
# removal cannot help: it only filters edges *within* a single shape.
# So the tiles' floor faces are stripped and replaced by one mesh shape for the
# whole level, which Jolt can then treat as a single continuous surface.
const FLOOR_Y := 0.0633          # tile floor surface, i.e. where the ball rests
const FLOOR_EPS := 0.001         # tolerance for "this face lies on the floor"

static var _tile_floors_stripped := false


func _build_smooth_floor() -> void:
    var grid := get_node_or_null(^"GridMap") as GridMap
    if grid == null or grid.mesh_library == null:
        return
    if not _tile_floors_stripped:
        _tile_floors_stripped = true
        _strip_tile_floors(grid.mesh_library)
        _rebuild_cells(grid)
    _add_floor_mesh(grid)


## Drop the tiles' floor slabs entirely - every face that lies at or below the
## floor plane. Walls (they start at the floor), ramps and bumps survive because
## they have vertices above it. Hole cups and the "gap" are left untouched so the
## ball can still drop in / fall through.
func _strip_tile_floors(lib: MeshLibrary) -> void:
    for id in lib.get_item_list():
        var item_name := String(lib.get_item_name(id)).to_lower()
        if item_name.contains("hole") or item_name == "gap":
            continue
        for entry in lib.get_item_shapes(id):
            if not (entry is ConcavePolygonShape3D):
                continue
            var shape: ConcavePolygonShape3D = entry
            var faces := shape.get_faces()
            var keep := PackedVector3Array()
            for i in range(0, faces.size(), 3):
                var a := faces[i]
                var b := faces[i + 1]
                var c := faces[i + 2]
                var top := maxf(a.y, maxf(b.y, c.y))
                if top <= FLOOR_Y + FLOOR_EPS:
                    continue
                keep.append(a)
                keep.append(b)
                keep.append(c)
            shape.set_faces(keep)


## Re-assign every cell so the GridMap rebuilds against the stripped library.
func _rebuild_cells(grid: GridMap) -> void:
    var cells := grid.get_used_cells()
    var items: Array[int] = []
    var orients: Array[int] = []
    for cell in cells:
        items.append(grid.get_cell_item(cell))
        orients.append(grid.get_cell_item_orientation(cell))
    for cell in cells:
        grid.set_cell_item(cell, -1)
    for i in cells.size():
        grid.set_cell_item(cells[i], items[i], orients[i])


## One concave shape holding the floor. Cells are merged into the largest
## rectangles possible so a straight corridor becomes a single quad - fewer
## internal edges for the ball to trip over.
func _add_floor_mesh(grid: GridMap) -> void:
    var pending := {}
    for cell in grid.get_used_cells():
        if not _has_no_floor(grid, cell):
            pending[cell] = true
    var faces := PackedVector3Array()
    while not pending.is_empty():
        var start: Vector3i = pending.keys()[0]
        var w := 1
        while pending.has(Vector3i(start.x + w, start.y, start.z)):
            w += 1
        var d := 1
        while _row_free(pending, start, w, d):
            d += 1
        for dz in d:
            for dx in w:
                pending.erase(Vector3i(start.x + dx, start.y, start.z + dz))
        _append_quad(faces, start, w, d)
    if faces.is_empty():
        return
    var shape := ConcavePolygonShape3D.new()
    shape.set_faces(faces)
    # Trimesh collision is one-sided by default; a floor should never let the
    # ball through regardless of which way the quads happen to be wound.
    shape.backface_collision = true
    var col := CollisionShape3D.new()
    col.shape = shape
    var body := StaticBody3D.new()
    body.name = "Floor"
    body.add_child(col)
    add_child(body)


func _row_free(pending: Dictionary, start: Vector3i, w: int, d: int) -> bool:
    for dx in w:
        if not pending.has(Vector3i(start.x + dx, start.y, start.z + d)):
            return false
    return true


## Emit one quad, wound so its normal points up.
func _append_quad(faces: PackedVector3Array, start: Vector3i, w: int, d: int) -> void:
    var a := Vector3(float(start.x), FLOOR_Y, float(start.z))
    var b := Vector3(float(start.x), FLOOR_Y, float(start.z + d))
    var c := Vector3(float(start.x + w), FLOOR_Y, float(start.z + d))
    var e := Vector3(float(start.x + w), FLOOR_Y, float(start.z))
    faces.append(a)
    faces.append(b)
    faces.append(c)
    faces.append(a)
    faces.append(c)
    faces.append(e)


## Cells that deliberately have no floor: hole cups (the ball must drop in) and
## the "gap" hazard (the ball must clear it).
func _has_no_floor(grid: GridMap, cell: Vector3i) -> bool:
    var item_name := String(grid.mesh_library.get_item_name(grid.get_cell_item(cell)))
    item_name = item_name.to_lower()
    return item_name.contains("hole") or item_name == "gap"


## World-space position where the ball should tee off.
func start_position() -> Vector3:
    return _start.global_position


## World-space position of the hole (the goal).
func hole_position() -> Vector3:
    return _hole.global_position


func _on_hole_entered(body: Node3D) -> void:
    if body is RigidBody3D and not _won:
        _ball = body
        _inside = true
        _hold = 0.0


func _on_hole_exited(body: Node3D) -> void:
    if body == _ball:
        _inside = false
        _hold = 0.0


func _physics_process(delta: float) -> void:
    if _won or not _inside or _ball == null:
        return
    if _ball.linear_velocity.length() <= max_speed:
        _hold += delta
        if _hold >= hold_time:
            _won = true
            level_over.emit()
    else:
        _hold = 0.0
