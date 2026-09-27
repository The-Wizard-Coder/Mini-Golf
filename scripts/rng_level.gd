extends GolfLevel
## Endless mode: builds a small hole from `seed_value`. The seed is the run
## counter, so the same seed always rebuilds the very same hole.
##
## The level is a walk across a cell grid. Every step of the walk is known, so
## each cell knows which of its four sides the ball has to pass through, and each
## tile is rotated until its baked walls agree with that. Nothing is taken on
## trust though: once the tiles are down the hole is flood filled from the tee,
## and a layout whose walls seal the cup off is thrown away and rebuilt rather
## than handed to the player.

@export var seed_value: int = 0
@export var min_tiles: int = 6
@export var max_tiles: int = 9
@export var straight_bias: float = 0.55   # odds of carrying on in the same direction
@export var max_attempts: int = 12        # layouts to try before giving up

const WALK_BOUNDS := 4                    # the walk stays inside a (2*B+1)^2 box
const MIN_PATH := 4                       # below this the tee would be the cup
const DIRS: Array[Vector2i] = [
    Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]

## Goal tiles. GolfLevel's floor mesh skips anything named "hole", which leaves
## the cup open for the ball to drop into.
const HOLES: Array[String] = ["hole-square", "hole-round"]

## Extra tiles the generator may drop into a corridor, each with the conditions
## it places on its neighbours and on itself before it is allowed to sit there.
##   from_hole        : run counter at which it starts appearing, so the first
##                      few maps stay plain and later ones get busier
##   min_index        : how far along the walk it may first appear, which keeps
##                      the tee area simple
##   straight_through : the path must run straight through the cell, so the ball
##                      meets it square on rather than part way round a turn
##   plain_neighbours : neither path neighbour may itself be a special tile
##   straight_run     : plain straight cells that have to lead into it first,
##                      which is what gives the ball room to build up speed
##   solid_after      : the cell beyond must be plain corridor, not the cup, so
##                      there is somewhere to land
const SPECIALS: Array[Dictionary] = [
    {
        "name": "tunnel-wide", "chance": 0.12,          # roofed stretch
        "from_hole": 1, "min_index": 2,
        "straight_through": false, "plain_neighbours": true, "straight_run": 0,
    },
    {
        "name": "narrow-square", "chance": 0.35,        # obstacle to steer around
        "from_hole": 3, "min_index": 3,
        "straight_through": true, "plain_neighbours": true, "straight_run": 0,
    },
    {
        "name": "hill-round", "chance": 0.18,           # rise to roll over
        "from_hole": 5, "min_index": 4,
        "straight_through": false, "plain_neighbours": true, "straight_run": 0,
        "solid_after": true,
    },
    {
        "name": "gap", "chance": 0.15,                  # jump, so it needs a run-up
        "from_hole": 7, "min_index": 5,
        "straight_through": true, "plain_neighbours": true, "straight_run": 2,
        "solid_after": true,
    },
]

var _grid: GridMap
var _lib: MeshLibrary
var _rot_index: Array[int] = []
var _placed: Dictionary = {}              # cell -> {item, orientation}

## Tile openings depend only on the baked mesh library, which never changes
## during a run, so they are worked out once per item and reused.
static var _openings_cache: Dictionary = {}


func _ready() -> void:
    _grid = $GridMap
    _lib = _grid.mesh_library
    _rot_index.clear()
    for k in 4:
        _rot_index.append(
            _grid.get_orthogonal_index_from_basis(Basis(Vector3.UP, k * PI * 0.5))
        )
    _build()
    super()


## Keep proposing layouts until one actually has an unbroken route from the tee
## to the cup. Every attempt is derived from the level's seed, so the accepted
## layout is still reproducible.
func _build() -> void:
    var last_path: Array[Vector2i] = []
    for attempt in max_attempts:
        var rng := RandomNumberGenerator.new()
        rng.seed = seed_value + attempt * 7919
        var path := _walk(rng)
        last_path = path
        if path.size() < MIN_PATH:
            continue                    # boxed in too early to make a hole
        var kinds := _base_kinds(path, rng)
        _try_specials(path, kinds, rng)
        _enforce_specials(path, kinds)
        _place(path, kinds)
        if _connects(path):
            _place_markers(path)
            return
    push_warning("rng_level: no connected layout for seed %d" % seed_value)
    if not last_path.is_empty():
        _place_markers(last_path)


# --- The walk ----------------------------------------------------------------

## Self-avoiding walk biased to keep going straight, so holes read as corridors
## rather than blobs. A new cell is never allowed to touch the rest of the path,
## which keeps every tile's walls unambiguous.
func _walk(rng: RandomNumberGenerator) -> Array[Vector2i]:
    var target := rng.randi_range(min_tiles, max_tiles)
    var path: Array[Vector2i] = [Vector2i.ZERO]
    var dir: Vector2i = DIRS[rng.randi_range(0, DIRS.size() - 1)]
    while path.size() < target:
        var tail: Vector2i = path[path.size() - 1]
        var found := false
        var picked := Vector2i.ZERO
        for d in _candidate_order(rng, dir):
            if _allowed(path, tail + d):
                picked = d
                found = true
                break
        if not found:
            break                       # boxed in; take the shorter hole
        path.append(tail + picked)
        dir = picked
    return path


## Straight first (usually), then the two turns, then doubling back last.
func _candidate_order(rng: RandomNumberGenerator, dir: Vector2i) -> Array[Vector2i]:
    var turns: Array[Vector2i] = []
    for d in DIRS:
        if d != dir and d != -dir:
            turns.append(d)
    for i in range(turns.size() - 1, 0, -1):    # seeded shuffle, not the global rng
        var j := rng.randi_range(0, i)
        var swap: Vector2i = turns[i]
        turns[i] = turns[j]
        turns[j] = swap
    var order: Array[Vector2i] = []
    var straight_first := rng.randf() < straight_bias
    if straight_first:
        order.append(dir)
    order.append_array(turns)
    order.append(-dir)
    if not straight_first:
        order.append(dir)
    return order


func _allowed(path: Array[Vector2i], next: Vector2i) -> bool:
    if absi(next.x) > WALK_BOUNDS or absi(next.y) > WALK_BOUNDS:
        return false
    if path.has(next):
        return false
    for i in path.size() - 1:           # everything except the tail we came from
        var delta: Vector2i = path[i] - next
        if absi(delta.x) + absi(delta.y) == 1:
            return false
    return true


# --- Turning the path into tiles ---------------------------------------------

## Plain layout first: a cap behind the tee, the goal at the far end, and
## straight or corner everywhere in between.
func _base_kinds(path: Array[Vector2i], rng: RandomNumberGenerator) -> Array[String]:
    var kinds: Array[String] = []
    for i in path.size():
        if i == 0:
            kinds.append("end")
        elif i == path.size() - 1:
            kinds.append(HOLES[rng.randi_range(0, HOLES.size() - 1)])
        else:
            kinds.append(_shape(path, i))
    return kinds


## Offer the specials to each plain cell and take the first one whose own
## conditions already hold where it stands.
func _try_specials(
    path: Array[Vector2i], kinds: Array[String], rng: RandomNumberGenerator
) -> void:
    for i in range(1, path.size() - 1):
        if kinds[i] != "straight" and kinds[i] != "corner":
            continue
        for spec in SPECIALS:
            if rng.randf() >= float(spec["chance"]):
                continue
            if not _spec_fits_here(path, kinds, i, spec):
                continue
            kinds[i] = spec["name"]
            break


func _spec_fits_here(
    path: Array[Vector2i], kinds: Array[String], i: int, spec: Dictionary
) -> bool:
    if seed_value < int(spec["from_hole"]) or i < int(spec["min_index"]):
        return false
    if bool(spec["straight_through"]) and _shape(path, i) != "straight":
        return false
    # If no quarter turn makes the tile face the way the path runs, it cannot go
    # here at all - forcing it would wall the route off.
    if _orientation(_item(spec["name"]), _openings_at(path, i)) < 0:
        return false
    return not _is_special(kinds[i - 1])


## Second pass: anything that ended up beside another special, or without the
## run-up or the landing it asked for, drops back to a plain tile.
func _enforce_specials(path: Array[Vector2i], kinds: Array[String]) -> void:
    for i in range(1, path.size() - 1):
        var spec := _special(kinds[i])
        if spec.is_empty():
            continue
        if bool(spec["plain_neighbours"]):
            var next_clear := i + 1 > path.size() - 2 or not _is_special(kinds[i + 1])
            if not next_clear or _is_special(kinds[i - 1]):
                kinds[i] = _shape(path, i)
                continue
        if bool(spec.get("solid_after", false)):
            if kinds[i + 1] != "straight" and kinds[i + 1] != "corner":
                kinds[i] = _shape(path, i)
                continue
        for k in range(1, int(spec["straight_run"]) + 1):
            var j := i - k
            if j < 1 or kinds[j] != "straight":
                kinds[i] = _shape(path, i)
                break


## Put the cells down. A tile that cannot be turned to face the way the path
## runs is not usable on that cell, so the plain shape goes there instead.
func _place(path: Array[Vector2i], kinds: Array[String]) -> void:
    _grid.clear()
    _placed.clear()
    for i in path.size():
        var wanted := _openings_at(path, i)
        var kind := kinds[i]
        var orientation := _orientation(_item(kind), wanted)
        if orientation < 0:
            var shape := _shape(path, i)
            if shape != "straight" and shape != "corner":
                continue                # a cap or goal that will not fit: give up
            kind = shape
            orientation = _orientation(_item(kind), wanted)
        var item := _item(kind)
        if item < 0 or orientation < 0:
            continue
        _grid.set_cell_item(Vector3i(path[i].x, 0, path[i].y), item, orientation)
        _placed[path[i]] = {"item": item, "orientation": orientation}


## Flood fill the placed cells from the tee. Openings come from the real tile
## geometry, so a tile that ended up rotated the wrong way reads as a wall here.
func _connects(path: Array[Vector2i]) -> bool:
    var goal: Vector2i = path[path.size() - 1]
    var start: Vector2i = path[1]
    if not _placed.has(start) or not _placed.has(goal):
        return false
    var seen := {start: true}
    var frontier: Array[Vector2i] = [start]
    while not frontier.is_empty():
        var cell: Vector2i = frontier.pop_back()
        if cell == goal:
            return true
        for d in _placed_openings(cell):
            var next: Vector2i = cell + d
            if _placed.has(next) and not seen.has(next):
                seen[next] = true
                frontier.append(next)
    return false


func _placed_openings(cell: Vector2i) -> Array[Vector2i]:
    if not _placed.has(cell):
        return []
    var entry: Dictionary = _placed[cell]
    var k := _rot_index.find(int(entry["orientation"]))
    if k < 0:
        return []
    var out: Array[Vector2i] = []
    for d in _openings(int(entry["item"])):
        out.append(_rot90(d, k))
    return out


func _item(tile: String) -> int:
    return _lib.find_item_by_name(tile)


func _special(tile: String) -> Dictionary:
    for spec in SPECIALS:
        if spec["name"] == tile:
            return spec
    return {}


func _is_special(tile: String) -> bool:
    return not _special(tile).is_empty()


## How the path runs through cell `i`: a dead end, straight through, or a turn.
func _shape(path: Array[Vector2i], i: int) -> String:
    if i == 0 or i == path.size() - 1:
        return "cap"
    var back := path[i - 1] - path[i]
    var ahead := path[i + 1] - path[i]
    return "straight" if back == -ahead else "corner"


## The sides of cell `i` the ball has to pass through.
func _openings_at(path: Array[Vector2i], i: int) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    if i > 0:
        out.append(path[i - 1] - path[i])
    if i < path.size() - 1:
        out.append(path[i + 1] - path[i])
    return out


## Tiles are authored in one base rotation; spin them in quarter turns until
## their openings match the ones this cell of the path needs. Returns -1 if no
## rotation does, i.e. the tile is simply not usable here.
func _orientation(item: int, wanted: Array[Vector2i]) -> int:
    if item < 0:
        return -1
    var natural := _openings(item)
    for k in 4:
        var rotated: Array[Vector2i] = []
        for d in natural:
            rotated.append(_rot90(d, k))
        if _same_set(rotated, wanted):
            return _rot_index[k]
    return -1


func _rot90(d: Vector2i, times: int) -> Vector2i:
    var out := d
    for i in times:
        out = Vector2i(out.y, -out.x)
    return out


func _same_set(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
    if a.size() != b.size():
        return false
    for d in a:
        if not b.has(d):
            return false
    return true


## Which cell sides a tile leaves open, read straight off its own collision
## geometry: the walls sit at the tile's outer extent, so a side with no faces
## there is a way through. Faces at or below the floor plane are the slab and are
## ignored.
func _openings(item: int) -> Array[Vector2i]:
    if _openings_cache.has(item):
        return _openings_cache[item]
    var tris: Array[PackedVector3Array] = []
    var reach := 0.0
    for entry in _lib.get_item_shapes(item):
        if not (entry is ConcavePolygonShape3D):
            continue
        var faces: PackedVector3Array = entry.get_faces()
        for i in range(0, faces.size(), 3):
            var tri := PackedVector3Array([faces[i], faces[i + 1], faces[i + 2]])
            if maxf(tri[0].y, maxf(tri[1].y, tri[2].y)) <= FLOOR_Y + FLOOR_EPS:
                continue
            tris.append(tri)
            for p in tri:
                reach = maxf(reach, maxf(absf(p.x), absf(p.z)))
    var edge := reach * 0.9
    var open: Array[Vector2i] = []
    for side in DIRS:
        # A side is walled only if the geometry flush against it actually spans
        # the tile. A wall box also has small end faces at the extremes, and
        # those must not read as a wall on the side they cap.
        var spans: Array[Vector2] = []
        for tri in tris:
            var flush := true
            var lo := INF
            var hi := -INF
            for p in tri:
                var along := p.x * float(side.x) + p.z * float(side.y)
                if along < edge:
                    flush = false
                    break
                var perp := p.z if side.x != 0 else p.x
                lo = minf(lo, perp)
                hi = maxf(hi, perp)
            if flush:
                spans.append(Vector2(lo, hi))
        if _coverage(spans) < 0.5:
            open.append(side)
    _openings_cache[item] = open
    return open


## Total length covered by a set of [lo, hi] spans, overlaps counted once.
func _coverage(spans: Array[Vector2]) -> float:
    if spans.is_empty():
        return 0.0
    spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
    var total := 0.0
    var hi := spans[0].x
    for s in spans:
        if s.y > hi:
            total += s.y - maxf(s.x, hi)
            hi = s.y
    return total


func _place_markers(path: Array[Vector2i]) -> void:
    $Start.position = _centre(path[1]) + Vector3(0, 0.3, 0)
    $HoleArea.position = _centre(path[path.size() - 1]) + Vector3(0, 0.15, 0)


func _centre(cell: Vector2i) -> Vector3:
    return Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)
