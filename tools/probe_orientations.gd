extends SceneTree
## Probe: print the Basis for each GridMap orthogonal orientation index.

func _init() -> void:
	var gm := GridMap.new()
	for i in range(24):
		var b: Basis = gm.get_basis_with_orthogonal_index(i)
		var e := b.get_euler()
		print("idx %2d : yaw=%.0f pitch=%.0f roll=%.0f" % [
			i, rad_to_deg(e.y), rad_to_deg(e.x), rad_to_deg(e.z)])
	quit()
