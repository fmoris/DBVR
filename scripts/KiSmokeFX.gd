extends RefCounted
class_name KiSmokeFX
## Pool ligero de humo volumétrico 3D para choques de Ki y explosiones en Meta Quest.
## Punto 7 del playtest: usa CPUParticles3D reutilizables con textura radial suave (cero GPU stall).

const POOL_SIZE: int = 4
static var _pool: Array[CPUParticles3D] = []
static var _pool_cursor: int = 0
static var _smoke_mesh: QuadMesh = null
static var _smoke_mat: StandardMaterial3D = null


static func _ensure_assets() -> void:
	if _smoke_mat == null:
		var grad := Gradient.new()
		grad.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 0.85), Color(0.9, 0.9, 0.9, 0.35), Color(0.8, 0.8, 0.8, 0.0)])
		grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		var tex := GradientTexture2D.new()
		tex.width = 64
		tex.height = 64
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.gradient = grad

		_smoke_mat = StandardMaterial3D.new()
		_smoke_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		_smoke_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		_smoke_mat.vertex_color_use_as_albedo = true
		_smoke_mat.billboard_mode = StandardMaterial3D.BILLBOARD_PARTICLES
		_smoke_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_smoke_mat.albedo_texture = tex

	if _smoke_mesh == null:
		_smoke_mesh = QuadMesh.new()
		_smoke_mesh.size = Vector2(1.0, 1.0)
		_smoke_mesh.material = _smoke_mat


static func _acquire_emitter(scene_root: Node) -> CPUParticles3D:
	_ensure_assets()
	# Limpiar referencias inválidas tras cambio de escena
	for i in range(_pool.size() - 1, -1, -1):
		if not is_instance_valid(_pool[i]) or not _pool[i].is_inside_tree():
			_pool.remove_at(i)

	if _pool.size() < POOL_SIZE:
		var p := CPUParticles3D.new()
		p.name = "KiSmokeEmitter_%d" % _pool.size()
		p.mesh = _smoke_mesh
		p.one_shot = true
		p.explosiveness = 0.85
		p.lifetime = 2.0
		p.amount = 14
		p.direction = Vector3.UP
		p.spread = 180.0
		p.gravity = Vector3(0.0, 0.45, 0.0)
		p.damping_min = 1.6
		p.damping_max = 2.8
		var col_ramp := Gradient.new()
		col_ramp.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 0.0), Color(0.9, 0.9, 0.9, 0.65), Color(0.75, 0.75, 0.75, 0.0)])
		col_ramp.offsets = PackedFloat32Array([0.0, 0.18, 1.0])
		p.color_ramp = col_ramp
		var sc_curve := Curve.new()
		sc_curve.add_point(Vector2(0.0, 0.45))
		sc_curve.add_point(Vector2(0.4, 1.15))
		sc_curve.add_point(Vector2(1.0, 1.85))
		p.scale_amount_curve = sc_curve
		scene_root.add_child(p)
		_pool.append(p)
		return p

	_pool_cursor = (_pool_cursor + 1) % _pool.size()
	return _pool[_pool_cursor]


static func spawn_smoke(tree: SceneTree, pos: Vector3, scale_mult: float = 1.0, tint: Color = Color(0.68, 0.66, 0.64, 0.70)) -> void:
	if not tree:
		return
	var parent_node: Node = tree.current_scene if tree.current_scene else tree.root
	if not parent_node:
		return
	var emitter: CPUParticles3D = _acquire_emitter(parent_node)
	if not emitter or not is_instance_valid(emitter):
		return
	emitter.global_position = pos
	emitter.initial_velocity_min = 1.4 * scale_mult
	emitter.initial_velocity_max = 3.4 * scale_mult
	emitter.scale_amount_min = 0.85 * scale_mult
	emitter.scale_amount_max = 1.65 * scale_mult
	emitter.color = tint
	emitter.emitting = false
	emitter.restart()
	emitter.emitting = true
