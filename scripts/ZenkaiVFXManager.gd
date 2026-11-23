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
static var _shared_billboard_quad: QuadMesh = null
static var _shared_pillar_mesh: CylinderMesh = null
static var _zenkai_ring_tex: Texture2D = null
static var _zenkai_flame_tex: Texture2D = null
static var _zenkai_band_tex: Texture2D = null
static var _tex_cache: Dictionary = {}

const TEX_PATHS: Dictionary = {
	"aura_streaks": "res://assets/vfx_zenkai/particles/aura/aura_vertical_streaks.png",
	"aura_band": "res://assets/vfx_zenkai/particles/aura/aura_flame_band.png",
	"aura_burst": "res://assets/vfx_zenkai/particles/aura/aura_flame_burst.png",
	"aura_v_white": "res://assets/vfx_zenkai/particles/aura/aura_v_flame_white.png",
	"aura_v_ssj": "res://assets/vfx_zenkai/particles/aura/aura_v_flame_ssj.png",
	"aura_v_ssb": "res://assets/vfx_zenkai/particles/aura/aura_v_flame_ssb.png",
	"aura_flare": "res://assets/vfx_zenkai/particles/aura/aura_upward_flare.png",
	"aura_spikes": "res://assets/vfx_zenkai/particles/aura/aura_radial_spikes.png",
	"lightning_4x4_white": "res://assets/vfx_zenkai/particles/lightning/lightning_4x4_white.png",
	"lightning_4x4_blue": "res://assets/vfx_zenkai/particles/lightning/lightning_4x4_blue.png",
	"lightning_arc_ring": "res://assets/vfx_zenkai/particles/lightning/lightning_arc_ring.png",
	"lightning_bolt_ring": "res://assets/vfx_zenkai/particles/lightning/lightning_bolt_ring.png",
	"ki_core_white": "res://assets/vfx_zenkai/particles/blast/ki_core_white.png",
	"ki_core_soft": "res://assets/vfx_zenkai/particles/blast/ki_core_soft.png",
	"ki_glow_halo": "res://assets/vfx_zenkai/particles/blast/ki_glow_halo.png",
	"ki_orb_shell": "res://assets/vfx_zenkai/particles/blast/ki_orb_shell.png",
	"ki_orb_rim": "res://assets/vfx_zenkai/particles/blast/ki_orb_rim.png",
	"ki_dome_fresnel": "res://assets/vfx_zenkai/particles/blast/ki_dome_fresnel.png",
	"ki_flash_star": "res://assets/vfx_zenkai/particles/blast/ki_flash_star.png",
	"ki_charge_vortex": "res://assets/vfx_zenkai/particles/blast/ki_charge_vortex.png",
	"ki_plasma": "res://assets/vfx_zenkai/particles/blast/ki_plasma_turbulence.png",
	"beam_core": "res://assets/vfx_zenkai/particles/beam/beam_core_strip.png",
	"beam_tail": "res://assets/vfx_zenkai/particles/beam/beam_tail_cone.png",
	"beam_ring_turb": "res://assets/vfx_zenkai/particles/beam/beam_ring_turbulent.png",
	"beam_ring_sharp": "res://assets/vfx_zenkai/particles/beam/beam_ring_sharp.png",
	"beam_ring_thick": "res://assets/vfx_zenkai/particles/beam/beam_ring_thick.png",
	"beam_speed_lines": "res://assets/vfx_zenkai/particles/beam/beam_speed_lines.png",
	"beam_charge_rays": "res://assets/vfx_zenkai/particles/beam/beam_charge_rays.png",
	"exp_fire_4x4": "res://assets/vfx_zenkai/particles/explosion/exp_fire_4x4.png",
	"exp_fireball_4x4": "res://assets/vfx_zenkai/particles/explosion/exp_fireball_4x4.png",
	"exp_blue_4x4": "res://assets/vfx_zenkai/particles/explosion/exp_blue_4x4.png",
	"exp_purple_4x4": "res://assets/vfx_zenkai/particles/explosion/exp_purple_4x4.png",
	"smoke_white_4x4": "res://assets/vfx_zenkai/particles/explosion/smoke_anime_white_4x4.png",
	"smoke_dust_4x4": "res://assets/vfx_zenkai/particles/explosion/smoke_anime_dust_4x4.png",
	"smoke_puff_4x4": "res://assets/vfx_zenkai/particles/explosion/smoke_puff_4x4.png",
	"smoke_ring": "res://assets/vfx_zenkai/particles/explosion/smoke_ring.png",
	"shockwave_ring": "res://assets/vfx_zenkai/particles/explosion/shockwave_ring.png",
	"debris_rocks_4x4": "res://assets/vfx_zenkai/particles/explosion/debris_rocks_4x4.png",
	"crater_cracks": "res://assets/vfx_zenkai/particles/explosion/crater_cracks.png",
	"impact_flash": "res://assets/vfx_zenkai/particles/impact/impact_flash_orange.png",
	"impact_sparks": "res://assets/vfx_zenkai/particles/impact/impact_sparks_burst.png",
	"impact_hit_white": "res://assets/vfx_zenkai/particles/impact/impact_hit_white.png",
	"impact_cross": "res://assets/vfx_zenkai/particles/impact/impact_cross_flare.png",
	"impact_lens": "res://assets/vfx_zenkai/particles/impact/impact_star_lens.png",
}


static func get_tex(key: String) -> Texture2D:
	if _tex_cache.has(key):
		return _tex_cache[key] as Texture2D
	var path: String = String(TEX_PATHS.get(key, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path) as Texture2D
	if tex != null:
		_tex_cache[key] = tex
	return tex


static func get_flame_tex() -> Texture2D:
	var t: Texture2D = get_tex("aura_streaks")
	if t != null:
		return t
	_ensure_shared_meshes()
	return _zenkai_flame_tex


static func get_band_tex() -> Texture2D:
	var t: Texture2D = get_tex("aura_band")
	if t != null:
		return t
	_ensure_shared_meshes()
	return _zenkai_band_tex


static func get_ring_tex() -> Texture2D:
	var t: Texture2D = get_tex("shockwave_ring")
	if t != null:
		return t
	_ensure_shared_meshes()
	return _zenkai_ring_tex


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

	if _shared_billboard_quad == null:
		_shared_billboard_quad = QuadMesh.new()
		_shared_billboard_quad.size = Vector2(2.0, 2.0)

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
	if _zenkai_flame_tex == null and ResourceLoader.exists("res://assets/vfx_zenkai/common/zenkai_skill_s_file18.png"):
		_zenkai_flame_tex = load("res://assets/vfx_zenkai/common/zenkai_skill_s_file18.png") as Texture2D
	if _zenkai_band_tex == null and ResourceLoader.exists("res://assets/vfx_zenkai/common/zenkai_skill_s_file2.png"):
		_zenkai_band_tex = load("res://assets/vfx_zenkai/common/zenkai_skill_s_file2.png") as Texture2D


static func _make_zenkai_sprite_mat(tex_key: String, col: Color, billboard: BaseMaterial3D.BillboardMode = BaseMaterial3D.BILLBOARD_ENABLED) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.billboard_mode = billboard
	mat.billboard_keep_scale = true
	var t: Texture2D = get_tex(tex_key)
	if t != null:
		mat.albedo_texture = t
	mat.albedo_color = col
	return mat


static func build_zenkai_orb_visual(
	parent: Node3D,
	radius: float,
	energy_color: Color,
	is_super: bool = false,
	has_lightning: bool = false
) -> Node3D:
	_ensure_shared_meshes()
	var orb := Node3D.new()
	orb.name = "ZenkaiKiOrb"
	orb.scale = Vector3.ONE * maxf(0.02, radius)

	var core_mi := MeshInstance3D.new()
	core_mi.name = "CoreSprite"
	core_mi.mesh = _shared_billboard_quad
	core_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core_mi.scale = Vector3.ONE * 0.92
	core_mi.material_override = _make_zenkai_sprite_mat("ki_core_soft", Color(1.0, 0.99, 0.95, 1.0))
	orb.add_child(core_mi)

	var shell_mi := MeshInstance3D.new()
	shell_mi.name = "ShellSprite"
	shell_mi.mesh = _shared_billboard_quad
	shell_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell_mi.scale = Vector3.ONE * 1.28
	shell_mi.material_override = _make_zenkai_sprite_mat("ki_orb_shell", Color(energy_color.r, energy_color.g, energy_color.b, 0.95))
	orb.add_child(shell_mi)

	var flare_mi := MeshInstance3D.new()
	flare_mi.name = "FlareSprite"
	flare_mi.mesh = _shared_billboard_quad
	flare_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flare_mi.scale = Vector3.ONE * (1.85 if is_super else 1.55)
	flare_mi.material_override = _make_zenkai_sprite_mat("ki_flash_star" if is_super else "ki_glow_halo", Color(energy_color.r, energy_color.g, energy_color.b, 0.85))
	orb.add_child(flare_mi)

	if is_super:
		var plasma_mi := MeshInstance3D.new()
		plasma_mi.name = "PlasmaSprite"
		plasma_mi.mesh = _shared_billboard_quad
		plasma_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		plasma_mi.scale = Vector3.ONE * 1.48
		plasma_mi.material_override = _make_zenkai_sprite_mat("ki_plasma", Color(energy_color.r, energy_color.g, energy_color.b, 0.80))
		orb.add_child(plasma_mi)

	if has_lightning:
		var bolt_mi := MeshInstance3D.new()
		bolt_mi.name = "LightningArcSprite"
		bolt_mi.mesh = _shared_billboard_quad
		bolt_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bolt_mi.scale = Vector3.ONE * 1.65
		bolt_mi.material_override = _make_zenkai_sprite_mat("lightning_arc_ring", Color(0.75, 0.95, 1.0, 0.92))
		orb.add_child(bolt_mi)

	if parent != null:
		parent.add_child(orb)
	return orb


static func spawn_zenkai_impact_flash(
	tree: SceneTree,
	pos: Vector3,
	col: Color,
	scale_mult: float = 1.0
) -> void:
	if not tree:
		return
	var scene_root: Node = tree.current_scene if tree.current_scene else tree.root
	if not scene_root:
		return
	_ensure_shared_meshes()

	var fx_root := Node3D.new()
	fx_root.name = "ZenkaiImpactFlash"
	scene_root.add_child(fx_root)
	fx_root.global_position = pos

	var hit_mi := MeshInstance3D.new()
	hit_mi.mesh = _shared_billboard_quad
	hit_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hit_mat: StandardMaterial3D = _make_zenkai_sprite_mat("impact_hit_white", Color(1.0, 0.98, 0.92, 1.0))
	hit_mi.material_override = hit_mat
	hit_mi.scale = Vector3.ONE * (0.45 * scale_mult)
	fx_root.add_child(hit_mi)

	var spark_mi := MeshInstance3D.new()
	spark_mi.mesh = _shared_billboard_quad
	spark_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spark_mat: StandardMaterial3D = _make_zenkai_sprite_mat("impact_sparks", Color(col.r, col.g, col.b, 0.95))
	spark_mi.material_override = spark_mat
	spark_mi.scale = Vector3.ONE * (0.65 * scale_mult)
	fx_root.add_child(spark_mi)

	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = _shared_billboard_quad
	ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring_mat: StandardMaterial3D = _make_zenkai_sprite_mat("shockwave_ring", Color(col.r, col.g, col.b, 0.90))
	ring_mi.material_override = ring_mat
	ring_mi.scale = Vector3.ONE * (0.40 * scale_mult)
	fx_root.add_child(ring_mi)

	var tw: Tween = fx_root.create_tween()
	tw.tween_property(hit_mi, "scale", Vector3.ONE * (1.15 * scale_mult), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(hit_mat, "albedo_color:a", 0.0, 0.16)
	tw.parallel().tween_property(spark_mi, "scale", Vector3.ONE * (1.85 * scale_mult), 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(spark_mat, "albedo_color:a", 0.0, 0.24)
	tw.parallel().tween_property(ring_mi, "scale", Vector3.ONE * (2.30 * scale_mult), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, 0.28)
	tw.tween_callback(fx_root.queue_free)


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
		if _zenkai_flame_tex:
			dome_mat.set_shader_parameter("plasma_tex", _zenkai_flame_tex)
		if _zenkai_band_tex:
			dome_mat.set_shader_parameter("streak_tex", _zenkai_band_tex)
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

	_spawn_zenkai_flipbook_burst(scene_root, pos, clamped_tier, radius_target, duration_sec, energy_color)


static func _pick_explosion_flipbook_key(energy_color: Color) -> String:
	if energy_color.b > energy_color.r * 1.25 and energy_color.b > 0.65:
		if energy_color.r > 0.45:
			return "exp_purple_4x4"
		return "exp_blue_4x4"
	if energy_color.r > 0.65 and energy_color.b > 0.65 and energy_color.g < 0.55:
		return "exp_purple_4x4"
	return "exp_fireball_4x4"


static func _spawn_zenkai_flipbook_burst(
	scene_root: Node,
	pos: Vector3,
	clamped_tier: int,
	radius_target: float,
	duration_sec: float,
	energy_color: Color
) -> void:
	var exp_key: String = _pick_explosion_flipbook_key(energy_color)
	var exp_tex: Texture2D = get_tex(exp_key)
	if exp_tex != null:
		var burst := CPUParticles3D.new()
		burst.name = "ZenkaiExplosionFlipbook"
		var quad := QuadMesh.new()
		quad.size = Vector2(radius_target * 1.15, radius_target * 1.15)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.billboard_keep_scale = true
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.particles_anim_h_frames = 4
		mat.particles_anim_v_frames = 4
		mat.particles_anim_loop = false
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = exp_tex
		quad.material = mat
		burst.mesh = quad
		burst.one_shot = true
		burst.explosiveness = 0.92
		burst.amount = clampi(2 + clamped_tier * 2, 3, 10)
		burst.lifetime = maxf(0.32, duration_sec * 0.85)
		burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		burst.emission_sphere_radius = maxf(0.15, radius_target * 0.25)
		burst.direction = Vector3.UP
		burst.spread = 180.0
		burst.gravity = Vector3(0.0, 0.6, 0.0)
		burst.initial_velocity_min = 0.5
		burst.initial_velocity_max = maxf(1.2, radius_target * 0.85)
		burst.anim_speed_min = 1.0
		burst.anim_speed_max = 1.35
		burst.color = Color(1.0, 0.98, 0.95, 0.96)
		scene_root.add_child(burst)
		burst.global_position = pos
		burst.emitting = true
		burst.finished.connect(burst.queue_free)

	if clamped_tier >= 3:
		var rocks_tex: Texture2D = get_tex("debris_rocks_4x4")
		if rocks_tex != null:
			var rocks := CPUParticles3D.new()
			rocks.name = "ZenkaiExplosionDebris"
			var rquad := QuadMesh.new()
			rquad.size = Vector2(0.38, 0.38)
			var rmat := StandardMaterial3D.new()
			rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			rmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			rmat.billboard_keep_scale = true
			rmat.particles_anim_h_frames = 4
			rmat.particles_anim_v_frames = 4
			rmat.particles_anim_loop = false
			rmat.albedo_texture = rocks_tex
			rquad.material = rmat
			rocks.mesh = rquad
			rocks.one_shot = true
			rocks.explosiveness = 1.0
			rocks.amount = 6 + clamped_tier * 2
			rocks.lifetime = 0.85
			rocks.direction = Vector3.UP
			rocks.spread = 75.0
			rocks.gravity = Vector3(0.0, -9.8, 0.0)
			rocks.initial_velocity_min = 4.0
			rocks.initial_velocity_max = 9.0
			rocks.anim_offset_min = 0.0
			rocks.anim_offset_max = 1.0
			scene_root.add_child(rocks)
			rocks.global_position = pos
			rocks.emitting = true
			rocks.finished.connect(rocks.queue_free)


static func spawn_zenkai_crater_decal(tree: SceneTree, pos: Vector3, radius: float, col: Color) -> void:
	if not tree:
		return
	var scene_root: Node = tree.current_scene if tree.current_scene else tree.root
	if not scene_root:
		return
	_ensure_shared_meshes()

	var crater := MeshInstance3D.new()
	crater.name = "ZenkaiCraterDecal"
	crater.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.2, radius * 2.2)
	crater.mesh = quad
	crater.rotation_degrees.x = -90.0

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var crack_tex: Texture2D = get_tex("crater_cracks")
	if crack_tex != null:
		mat.albedo_texture = crack_tex
	mat.albedo_color = Color(col.r, col.g, col.b, 0.88)
	crater.material_override = mat

	scene_root.add_child(crater)
	crater.global_position = pos

	var fade_tw := tree.create_tween()
	if fade_tw:
		fade_tw.tween_property(mat, "albedo_color:a", 0.0, 5.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		fade_tw.tween_callback(crater.queue_free)
