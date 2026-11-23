extends RefCounted
class_name ZenkaiVFXManager

const ExplosionDomeShader = preload("res://shaders/ki_explosion_dome.gdshader")
const ShockwaveShader = preload("res://shaders/shockwave.gdshader")

const DOME_POOL_SIZE: int = 5
const LIGHT_POOL_SIZE: int = 4

static var _dome_pool: Array[Node3D] = []
static var _dome_cursor: int = 0
static var _light_pool: Array[OmniLight3D] = []
static var _light_cursor: int = 0
static var _shared_dome_mesh: SphereMesh = null
static var _shared_ring_mesh: QuadMesh = null
static var _shared_pillar_mesh: CylinderMesh = null
static var _zenkai_ring_tex: Texture2D = null


static func _ensure_shared_meshes() -> void:
	if _shared_dome_mesh == null:
		_shared_dome_mesh = SphereMesh.new()
		_shared_dome_mesh.radius = 1.0
		_shared_dome_mesh.height = 2.0
		_shared_dome_mesh.radial_segments = 20
		_shared_dome_mesh.rings = 10

	if _shared_ring_mesh == null:
		_shared_ring_mesh = QuadMesh.new()
		_shared_ring_mesh.size = Vector2(2.0, 2.0)

	if _shared_pillar_mesh == null:
		_shared_pillar_mesh = CylinderMesh.new()
		_shared_pillar_mesh.top_radius = 1.15
		_shared_pillar_mesh.bottom_radius = 1.45
		_shared_pillar_mesh.height = 14.0
		_shared_pillar_mesh.radial_segments = 16
		_shared_pillar_mesh.cap_top = false
		_shared_pillar_mesh.cap_bottom = false

	if _zenkai_ring_tex == null and ResourceLoader.exists("res://assets/vfx_zenkai/common/zenkai_ring.png"):
		_zenkai_ring_tex = load("res://assets/vfx_zenkai/common/zenkai_ring.png") as Texture2D


static func _acquire_dome_node(scene_root: Node) -> Node3D:
	_ensure_shared_meshes()
	for i in range(_dome_pool.size() - 1, -1, -1):
		if not is_instance_valid(_dome_pool[i]) or not _dome_pool[i].is_inside_tree():
			_dome_pool.remove_at(i)

	if _dome_pool.size() < DOME_POOL_SIZE:
		var root_node := Node3D.new()
		root_node.name = "ZenkaiExplosionDome_%d" % _dome_pool.size()

		var dome_mi := MeshInstance3D.new()
		dome_mi.name = "DomeMesh"
		dome_mi.mesh = _shared_dome_mesh
		dome_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var dome_mat := ShaderMaterial.new()
		dome_mat.shader = ExplosionDomeShader
		dome_mi.material_override = dome_mat
		root_node.add_child(dome_mi)

		var ring_mi := MeshInstance3D.new()
		ring_mi.name = "RingMesh"
		ring_mi.mesh = _shared_ring_mesh
		ring_mi.rotation_degrees.x = -90.0
		ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ring_mat := ShaderMaterial.new()
		ring_mat.shader = ShockwaveShader
		ring_mat.set_shader_parameter("use_uv_ring", 1.0)
		ring_mi.material_override = ring_mat
		root_node.add_child(ring_mi)

		var pillar_mi := MeshInstance3D.new()
		pillar_mi.name = "PillarMesh"
		pillar_mi.mesh = _shared_pillar_mesh
		pillar_mi.position = Vector3(0.0, 6.5, 0.0)
		pillar_mi.visible = false
		pillar_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pillar_mi.material_override = dome_mat
		root_node.add_child(pillar_mi)

		root_node.visible = false
		scene_root.add_child(root_node)
		_dome_pool.append(root_node)
		return root_node

	_dome_cursor = (_dome_cursor + 1) % _dome_pool.size()
	return _dome_pool[_dome_cursor]


static func _acquire_light(scene_root: Node) -> OmniLight3D:
	for i in range(_light_pool.size() - 1, -1, -1):
		if not is_instance_valid(_light_pool[i]) or not _light_pool[i].is_inside_tree():
			_light_pool.remove_at(i)

	if _light_pool.size() < LIGHT_POOL_SIZE:
		var l := OmniLight3D.new()
		l.name = "ZenkaiKiLight_%d" % _light_pool.size()
		l.shadow_enabled = false
		l.light_energy = 0.0
		l.visible = false
		scene_root.add_child(l)
		_light_pool.append(l)
		return l

	_light_cursor = (_light_cursor + 1) % _light_pool.size()
	return _light_pool[_light_cursor]


static func spawn_zenkai_explosion(
	tree: SceneTree,
	pos: Vector3,
	tier: int,
	energy_color: Color,
	has_bio_lightning: bool = false
) -> void:
	if not tree:
		return
	var scene_root: Node = tree.current_scene if tree.current_scene else tree.root
	if not scene_root:
		return

	var clamped_tier: int = clampi(tier, 1, 5)
	var radius_target: float = 0.75
	var duration_sec: float = 0.25
	var light_range: float = 2.5
	var light_peak: float = 1.6

	match clamped_tier:
		1:
			radius_target = 0.70
			duration_sec = 0.20
			light_range = 2.2
			light_peak = 1.5
		2:
			radius_target = 1.55
			duration_sec = 0.35
			light_range = 3.8
			light_peak = 2.3
		3:
			radius_target = 2.85
			duration_sec = 0.48
			light_range = 5.5
			light_peak = 3.2
		4:
			radius_target = 5.20
			duration_sec = 0.82
			light_range = 10.0
			light_peak = 4.0
		5:
			radius_target = 11.50
			duration_sec = 1.35
			light_range = 18.0
			light_peak = 4.8

	var dome_root: Node3D = _acquire_dome_node(scene_root)
	if dome_root and is_instance_valid(dome_root):
		if dome_root.is_inside_tree():
			dome_root.global_position = pos
		else:
			dome_root.position = pos
		dome_root.visible = true

		var dome_mi := dome_root.get_node_or_null("DomeMesh") as MeshInstance3D
		var ring_mi := dome_root.get_node_or_null("RingMesh") as MeshInstance3D
		var pillar_mi := dome_root.get_node_or_null("PillarMesh") as MeshInstance3D

		var dome_mat: ShaderMaterial = dome_mi.material_override as ShaderMaterial if dome_mi else null
		var ring_mat: ShaderMaterial = ring_mi.material_override as ShaderMaterial if ring_mi else null

		if dome_mat:
			dome_mat.set_shader_parameter("outer_color", Color(energy_color.r, energy_color.g, energy_color.b, 0.95))
			dome_mat.set_shader_parameter("core_color", Color(1.0, 0.98, 0.92, 1.0))
			dome_mat.set_shader_parameter("progress", 0.0)
			dome_mat.set_shader_parameter("intensity", 2.4 + float(clamped_tier) * 0.45)
			dome_mat.set_shader_parameter("has_bio_lightning", 1.0 if (has_bio_lightning or clamped_tier >= 4) else 0.0)

		if ring_mat:
			ring_mat.set_shader_parameter("ring_color", Color(energy_color.r, energy_color.g, energy_color.b, 0.92))
			ring_mat.set_shader_parameter("progress", 0.0)
			ring_mat.set_shader_parameter("thickness", 0.16)

		if dome_mi:
			dome_mi.scale = Vector3.ONE * (radius_target * 0.22)
		if ring_mi:
			ring_mi.scale = Vector3.ONE * (radius_target * 0.35)
		if pillar_mi:
			pillar_mi.visible = (clamped_tier >= 5)
			pillar_mi.scale = Vector3(1.0, 0.2, 1.0)

		var tw := dome_root.create_tween()
		tw.set_parallel(true)
		if dome_mi:
			tw.tween_property(dome_mi, "scale", Vector3.ONE * radius_target, duration_sec).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if ring_mi:
			tw.tween_property(ring_mi, "scale", Vector3.ONE * (radius_target * 1.65), duration_sec).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if pillar_mi and clamped_tier >= 5:
			tw.tween_property(pillar_mi, "scale", Vector3(1.4, 1.5, 1.4), duration_sec).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if dome_mat:
			tw.tween_property(dome_mat, "shader_parameter/progress", 1.0, duration_sec)
		if ring_mat:
			tw.tween_property(ring_mat, "shader_parameter/progress", 1.0, duration_sec)
		tw.chain().tween_callback(func() -> void:
			if is_instance_valid(dome_root):
				dome_root.visible = false
		)

	var light: OmniLight3D = _acquire_light(scene_root)
	if light and is_instance_valid(light):
		if light.is_inside_tree():
			light.global_position = pos + Vector3(0.0, 0.35, 0.0)
		else:
			light.position = pos + Vector3(0.0, 0.35, 0.0)
		light.light_color = energy_color.lerp(Color.WHITE, 0.25)
		light.omni_range = light_range
		light.light_energy = light_peak
		light.visible = true
		var ltw := light.create_tween()
		ltw.tween_property(light, "light_energy", 0.0, duration_sec).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ltw.tween_callback(func() -> void:
			if is_instance_valid(light):
				light.visible = false
		)
