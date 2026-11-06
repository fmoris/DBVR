extends MeshInstance3D

func _process(delta: float) -> void:
	rotate_y(0.6 * delta)
