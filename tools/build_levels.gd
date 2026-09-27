extends SceneTree
## One-off tool: generate the level scenes (scenes/levels/level_N.tscn).
## Data-driven: each level is a list of [cell, item_id, orientation].
## Orientation (GridMap orthogonal index): Y0=0, Y90=16, Y180=10, Y270=22.
## Run headless: godot --headless --path . --script res://tools/build_levels.gd

const LIB := "res://assets/golf-kit/mesh_library.tres"
const LEVEL_SCRIPT := "res://scripts/level.gd"
const OUT_DIR := "res://scenes/levels/"

# MeshLibrary item ids
const HOLE := 28          # hole-square
const STRAIGHT := 105
const END := 15
const GAP := 22
const BUMP := 8
const CORNER := 13
const INNER_CORNER := 29
const NARROW := 30        # narrow-block
const NARROW_S := 32      # narrow-square

# GridMap orthogonal orientations (pure Y rotations)
const Y0 := 0
const Y90 := 16
const Y180 := 10
const Y270 := 22
const S := 105


func _init() -> void:
	_build()


func _set_owners(node: Node, owner: Node) -> void:
	for c in node.get_children():
		c.owner = owner
		_set_owners(c, owner)


func _make_level(fname: String, cells: Array, start_cell: Vector3i, hole_cell: Vector3i) -> void:
	var gm := GridMap.new()
	gm.name = "GridMap"
	gm.mesh_library = load(LIB)
	gm.cell_size = Vector3(1, 1, 1)
	gm.cell_center_y = false

	for c in cells:
		var p: Vector3i = c[0]
		var item: int = c[1]
		var orient: int = c[2]
		gm.set_cell_item(p, item, orient)

	var start := Marker3D.new()
	start.name = "Start"
	start.position = Vector3(start_cell.x + 0.5, 0.3, start_cell.z + 0.5)

	var hole_area := Area3D.new()
	hole_area.name = "HoleArea"
	hole_area.position = Vector3(hole_cell.x + 0.5, 0.15, hole_cell.z + 0.5)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.5, 0.4)
	cs.shape = box
	hole_area.add_child(cs)

	var root := Node3D.new()
	root.name = "Level"
	root.set_script(load(LEVEL_SCRIPT))
	root.add_child(gm)
	root.add_child(start)
	root.add_child(hole_area)
	_set_owners(root, root)

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack failed: %d" % err)
		return
	err = ResourceSaver.save(packed, OUT_DIR + fname + ".tscn")
	print("SAVED\t%s\terr=%d" % [fname, err])


func _build() -> void:
	# 0: the proven straight corridor.
	_make_level("level_0", [
		[Vector3i(0, 0, 1), HOLE, Y270],
		[Vector3i(1, 0, 1), STRAIGHT, Y270],
		[Vector3i(2, 0, 1), STRAIGHT, Y270],
		[Vector3i(3, 0, 1), STRAIGHT, Y270],
		[Vector3i(4, 0, 1), STRAIGHT, Y270],
		[Vector3i(5, 0, 1), END, Y90],
	], Vector3i(4, 0, 1), Vector3i(0, 0, 1))

	# 1: L-shaped turn (corner@16 connects -X and +Z).
	_make_level("level_1", [
		[Vector3i(0, 0, 1), HOLE, Y270],
		[Vector3i(1, 0, 1), STRAIGHT, Y270],
		[Vector3i(2, 0, 1), STRAIGHT, Y270],
		[Vector3i(3, 0, 1), CORNER, Y90],
		[Vector3i(3, 0, 2), STRAIGHT, Y0],
		[Vector3i(3, 0, 3), STRAIGHT, Y0],
		[Vector3i(3, 0, 4), END, Y0],
	], Vector3i(3, 0, 3), Vector3i(0, 0, 1))

	# 2: Z-bend with a narrow section (corner@16 then corner@22).
	_make_level("level_2", [
		[Vector3i(0, 0, 1), HOLE, Y270],
		[Vector3i(1, 0, 1), STRAIGHT, Y270],
		[Vector3i(2, 0, 1), NARROW, Y270],
		[Vector3i(3, 0, 1), CORNER, Y90],
		[Vector3i(3, 0, 2), STRAIGHT, Y0],
		[Vector3i(3, 0, 3), CORNER, Y270],
		[Vector3i(4, 0, 3), STRAIGHT, Y270],
		[Vector3i(5, 0, 3), END, Y90],
	], Vector3i(4, 0, 3), Vector3i(0, 0, 1))

	# 3: straight with a gap, a bump and a narrow tile.
	_make_level("level_3", [
		[Vector3i(0, 0, 1), HOLE, Y270],
		[Vector3i(1, 0, 1), STRAIGHT, Y270],
		[Vector3i(2, 0, 1), BUMP, Y270],
		[Vector3i(3, 0, 1), STRAIGHT, Y270],
		[Vector3i(4, 0, 1), GAP, Y270],
		[Vector3i(5, 0, 1), NARROW, Y270],
		[Vector3i(6, 0, 1), STRAIGHT, Y270],
		[Vector3i(7, 0, 1), END, Y90],
	], Vector3i(7, 0, 1), Vector3i(0, 0, 1))

	quit(0)
