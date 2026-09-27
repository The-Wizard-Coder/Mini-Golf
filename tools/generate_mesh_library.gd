extends SceneTree
## One-off tool: build a GridMap MeshLibrary from the minigolf-kit GLBs,
## each with a trimesh (ConcavePolygonShape3D) collider.
## Run headless: godot --headless --path . --script res://tools/generate_mesh_library.gd

const KIT_DIR := "res://assets/golf-kit/"
const OUT_PATH := "res://assets/golf-kit/mesh_library.tres"
const TOON_SHADER := "res://shaders/toon.gdshader"
const COLORMAP := "res://assets/golf-kit/Textures/colormap.png"


func _init() -> void:
	_build()


func _build() -> void:
	var dir := DirAccess.open(KIT_DIR)
	if dir == null:
		push_error("Cannot open " + KIT_DIR)
		quit(1)
		return

	var names: Array = []
	for f in dir.get_files():
		if f.ends_with(".glb"):
			names.append(f)
	names.sort()

	var toon_mat := ShaderMaterial.new()
	toon_mat.shader = load(TOON_SHADER)
	toon_mat.set_shader_parameter("albedo_tex", load(COLORMAP))

	var lib := MeshLibrary.new()
	var id := 0
	for fname in names:
		var scene: PackedScene = load(KIT_DIR + fname)
		if scene == null:
			push_warning("skip (load fail): " + fname)
			continue
		var inst: Node = scene.instantiate()
		var mesh := _extract_mesh(inst)
		inst.free()
		if mesh == null:
			push_warning("skip (no mesh): " + fname)
			continue
		for s in range(mesh.get_surface_count()):
			mesh.surface_set_material(s, toon_mat)
		var shape := mesh.create_trimesh_shape()
		lib.create_item(id)
		lib.set_item_name(id, fname.get_basename())
		lib.set_item_mesh(id, mesh)
		if shape != null:
			lib.set_item_shapes(id, [shape])
		print("ITEM\t%d\t%s" % [id, fname.get_basename()])
		id += 1

	var err := ResourceSaver.save(lib, OUT_PATH)
	print("SAVED\t%s\terr=%d\titems=%d" % [OUT_PATH, err, id])
	quit(0 if err == OK else 1)


## Use the original mesh directly when it's a single mesh at identity transform —
## this preserves the GLB's materials + embedded textures exactly. Only merge
## (via SurfaceTool) when the model has multiple meshes / a non-identity transform.
func _extract_mesh(root: Node) -> Mesh:
	var meshes := _find_meshes(root)
	if meshes.size() == 1:
		var mi: MeshInstance3D = meshes[0]
		if mi.mesh != null and _combined_transform(mi).is_equal_approx(Transform3D.IDENTITY):
			return mi.mesh
	return _merge_meshes(root)


func _merge_meshes(root: Node) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for mi in _find_meshes(root):
		var m: Mesh = mi.mesh
		if m == null:
			continue
		var xform := _combined_transform(mi)
		for si in m.get_surface_count():
			var mat := m.surface_get_material(si)
			if mat != null:
				st.set_material(mat)
			st.append_from(m, si, xform)
			count += 1
	if count == 0:
		return null
	return st.commit()


## Walk the instantiated parent chain (works outside the SceneTree, unlike
## Node3D.get_global_transform() which requires being inside the tree).
func _combined_transform(node: Node3D) -> Transform3D:
	var t := node.transform
	var p := node.get_parent()
	while p != null and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _find_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_meshes(child))
	return out
