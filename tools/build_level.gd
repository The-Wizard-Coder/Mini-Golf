extends SceneTree
## One-off tool: build a straight "objective" minigolf level — a simple corridor
## with the tee at one end and the hole directly opposite at the other.
## Run headless: godot --headless --path . --script res://tools/build_level.gd

const LIB_PATH := "res://assets/golf-kit/mesh_library.tres"
const OUT_PATH := "res://scenes/level.tscn"

# MeshLibrary item ids (from generate_mesh_library.gd output)
const OPEN := 36
const BLOCK := 4
const HOLE_ROUND := 27
const FLAG_RED := 21


func _init() -> void:
	_build()


func _build() -> void:
	var lib: MeshLibrary = load(LIB_PATH)
	if lib == null:
		push_error("cannot load " + LIB_PATH)
		quit(1)
		return

	var gm := GridMap.new()
	gm.name = "GridMap"
	gm.mesh_library = lib
	gm.cell_size = Vector3(1, 1, 1)
	gm.cell_center_x = true
	gm.cell_center_y = false
	gm.cell_center_z = true

	# Straight corridor floor: 10 long (x 0..9) x 3 wide (z 1..3).
	for x in range(0, 10):
		for z in range(1, 4):
			gm.set_cell_item(Vector3i(x, 0, z), OPEN)

	# Perimeter walls (blocks).
	for x in range(0, 10):
		gm.set_cell_item(Vector3i(x, 0, 0), BLOCK)   # near wall
		gm.set_cell_item(Vector3i(x, 0, 4), BLOCK)   # far wall
	for z in range(0, 5):
		gm.set_cell_item(Vector3i(-1, 0, z), BLOCK)  # tee-end wall
		gm.set_cell_item(Vector3i(10, 0, z), BLOCK)  # hole-end wall

	# Objective: hole at the far end, flag beside it.
	gm.set_cell_item(Vector3i(9, 0, 2), HOLE_ROUND)
	gm.set_cell_item(Vector3i(9, 0, 3), FLAG_RED)

	var root := Node3D.new()
	root.name = "Level"
	root.add_child(gm)
	gm.owner = root

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack failed: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT_PATH)
	print("SAVED\t%s\terr=%d" % [OUT_PATH, err])
	quit(0 if err == OK else 1)
